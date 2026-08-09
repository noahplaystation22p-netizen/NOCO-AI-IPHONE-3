import AVFoundation
import Foundation
import Speech
import UIKit

enum VoicePhase: Equatable {
    case idle
    case listening
    case processing
    case speaking
    case error(String)
}

@MainActor
final class VoiceService: NSObject, ObservableObject {
    @Published var phase: VoicePhase = .idle
    @Published var liveTranscript = ""
    @Published var level: CGFloat = 0
    @Published var bands: [CGFloat] = Array(repeating: 0.12, count: 16)
    @Published var isAuthorized = false
    @Published var sessionActive = false
    /// When true: mic off, no auto-send — TTS still plays.
    @Published var isMuted = false
    /// Text revealed in sync with TTS playback (not the full reply up front).
    @Published var spokenVisibleText = ""

    var onAutoUtterance: ((String) -> Void)?
    var onSpeakFinished: (() -> Void)?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let synthesizer = AVSpeechSynthesizer()

    private var noiseFloor: CGFloat = 0.02
    private var speechStarted = false
    private var speechStartAt: Date?
    private var lastVoiceAt: Date?
    private var lastTranscriptChangeAt: Date?
    private var lastTranscript = ""
    private var silenceTask: Task<Void, Never>?
    private var autoFinishArmed = false
    private var pendingSpeakChunks = 0
    private var speakFinishedNotified = false
    /// Bumped on each `speak()` / stop so late PCM callbacks from a prior utterance are ignored.
    private var speakGeneration: UInt64 = 0
    private var speakingStartedAt: Date?
    private var recognitionStartedAt: Date?
    private var audioObserversInstalled = false
    private var inputTapInstalled = false
    private var lastAudioBufferAt: Date?
    private var audioBufferCount: UInt64 = 0

    /// Amplified TTS path (gain > 1.0 — AVSpeechUtterance.volume alone caps at 1).
    private let ttsEngine = AVAudioEngine()
    private let ttsPlayer = AVAudioPlayerNode()
    private var ttsEngineReady = false
    private var ttsUseAmplified = false
    private var ttsPendingBuffers = 0
    /// Ensures TTS_PLAYBACK_START is logged once per utterance.
    private var didLogTTSPlaybackStart = false
    /// Bridge/filler TTS must not trigger return-to-listen mid-turn.
    private var suppressSpeakFinishedNotify = false

    /// Wait for a clear end of speech — responsive, but not mid-thought.
    private let silenceToEnd: TimeInterval = 0.86
    private let transcriptStableToEnd: TimeInterval = 0.62
    private let minSpeechSeconds: TimeInterval = 0.38
    private let naturalEndQuiet: TimeInterval = 0.72
    private let endConfirmGrace: TimeInterval = 0.16
    private let speechLevelFactor: CGFloat = 2.35

    private var pendingEndCandidateAt: Date?
    /// Soft barge-in while TTS plays (Voice AI).
    private var bargeInArmed = false
    private var bargeInTask: Task<Void, Never>?
    var onBargeIn: ((String) -> Void)?
    /// Spoken text currently playing — used to ignore TTS echo as barge-in.
    private var speakingTextLower = ""
    /// Ordered TTS chunks for progressive UI reveal.
    private var speakChunksOrdered: [String] = []
    private var revealedSpeakChunkCount = 0
    private var speakChunkDidReveal: [Bool] = []
    /// Index of the utterance currently being spoken on the fallback (non-amplified) path.
    private var fallbackSpeakChunkCursor = 0

    var preferredVoiceIdentifier: String {
        get { NOCOSpeakVoiceSettings.voiceIdentifier }
        set { NOCOSpeakVoiceSettings.voiceIdentifier = newValue }
    }

    var autoSpeakReplies: Bool {
        get {
            if UserDefaults.standard.object(forKey: "nocoai.autoSpeak") == nil { return true }
            return UserDefaults.standard.bool(forKey: "nocoai.autoSpeak")
        }
        set { UserDefaults.standard.set(newValue, forKey: "nocoai.autoSpeak") }
    }

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
        NOCOSpeakVoiceSettings.ensureDefaults()
        installAudioSessionObservers()
    }

    private func installAudioSessionObservers() {
        guard !audioObserversInstalled else { return }
        audioObserversInstalled = true
        let center = NotificationCenter.default
        center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                self?.handleAudioInterruption(note)
            }
        }
        center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleRouteChange()
            }
        }
        center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleMediaServicesReset()
            }
        }
    }

    private func handleAudioInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let typeVal = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeVal) else { return }
        switch type {
        case .began:
            VoiceDebugLog.event("AUDIO_INTERRUPTION", "began \(pipelineDebugSummary())")
            if case .listening = phase {
                stopListening(cancel: true)
                phase = .idle
            }
        case .ended:
            VoiceDebugLog.event("AUDIO_INTERRUPTION", "ended \(pipelineDebugSummary())")
            let opts = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                .flatMap { AVAudioSession.InterruptionOptions(rawValue: $0) } ?? []
            guard opts.contains(.shouldResume), sessionActive, !isMuted else { return }
            if case .speaking = phase { return }
            try? activateListeningAfterTTS()
            // Health loop / SpeakSession will reopen mic; mark idle so it can.
            if case .listening = phase, !isActivelyListening {
                phase = .idle
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange() {
        guard sessionActive, !isMuted else { return }
        VoiceDebugLog.event("AUDIO_ROUTE_CHANGE", pipelineDebugSummary())
        if case .speaking = phase { return }
        // After BT / speaker flips, recognition often dies silently.
        if case .listening = phase, !audioEngine.isRunning {
            phase = .idle
        }
    }

    private func handleMediaServicesReset() {
        stopTTSEngine()
        ttsEngineReady = false
        if case .speaking = phase {
            stopSpeaking(notifyFinished: true)
        }
        if case .listening = phase {
            stopListening(cancel: true)
            phase = .idle
        }
        if sessionActive {
            try? activateBackgroundAudioSession()
        }
    }

    func requestPermissions() async -> Bool {
        let mic = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
        }
        let speech = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        isAuthorized = mic && speech && (speechRecognizer?.isAvailable ?? false)
        return isAuthorized
    }

    /// Mic + background-capable duplex session.
    func activateBackgroundAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        VoiceDebugLog.event("AUDIO_SESSION_CONFIGURE", "playAndRecord.voiceChat")
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
        )
        try session.overrideOutputAudioPort(.speaker)
        try session.setActive(true, options: [])
        VoiceDebugLog.event("AUDIO_SESSION_ACTIVE", "input=\(session.isInputAvailable)")
    }

    /// Loud TTS route — during an active Speak session keep duplex so background mic survives.
    func activateLoudPlaybackSession() throws {
        let session = AVAudioSession.sharedInstance()
        VoiceDebugLog.event("AUDIO_SESSION_CONFIGURE", sessionActive ? "duplex_tts" : "playback_tts")
        if sessionActive {
            // Pure `.playback` after filler TTS often kills Island/background follow-ups.
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
            )
        } else {
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.defaultToSpeaker, .allowBluetoothA2DP]
            )
        }
        try session.overrideOutputAudioPort(.speaker)
        try session.setActive(true, options: [])
        VoiceDebugLog.event("AUDIO_SESSION_ACTIVE", "tts")
    }

    /// Back to mic after TTS — never fully deactivate (that suspends background Voice AI).
    func activateListeningAfterTTS() throws {
        let session = AVAudioSession.sharedInstance()
        VoiceDebugLog.event("AUDIO_SESSION_RECONFIGURE", "listen_after_tts")
        // Soft route flip only — `setActive(false)` drops UIBackgroundModes.audio keep-alive.
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
        )
        try session.overrideOutputAudioPort(.speaker)
        try session.setActive(true, options: [])
        VoiceDebugLog.event("AUDIO_SESSION_ACTIVE", "listen input=\(session.isInputAvailable)")
    }

    /// Tear down TTS + recognition, then rebuild a clean duplex session for the next listen turn.
    /// Call this after every reply before `startListening` — do not reuse a damaged post-TTS route.
    func hardReinitAudioForListen() throws {
        VoiceDebugLog.event("AUDIO_SESSION_REACTIVATED", "hard_reinit")
        cancelBargeIn()
        // Do NOT bump speakGeneration here if TTS already finished — avoid racing a late finish.
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        stopTTSEngine()
        ttsUseAmplified = false
        pendingSpeakChunks = 0
        ttsPendingBuffers = 0
        speakingStartedAt = nil
        speakingTextLower = ""
        let keepWarm = sessionActive && audioEngine.isRunning
        clearRecognitionPipeline(cancel: true, keepAudioEngineRunning: keepWarm, reason: keepWarm ? "hard_reinit_keep_warm" : "hard_reinit")
        if case .speaking = phase { phase = .idle }
        try activateListeningAfterTTS()
        // Validate input hardware settled after route flip.
        var format = audioEngine.inputNode.outputFormat(forBus: 0)
        if format.sampleRate <= 0 || format.channelCount <= 0 {
            try activateBackgroundAudioSession()
            format = audioEngine.inputNode.outputFormat(forBus: 0)
        }
        if format.sampleRate <= 0 || format.channelCount <= 0 {
            throw ListenError.micNotReady
        }
    }

    func startListening(autoEnd: Bool = true) throws {
        guard !isMuted else {
            phase = .idle
            throw ListenError.muted
        }
        stopSpeaking(notifyFinished: false)
        let keepWarm = sessionActive && audioEngine.isRunning
        clearRecognitionPipeline(cancel: true, keepAudioEngineRunning: keepWarm, reason: keepWarm ? "start_listen_keep_warm" : "start_listen")
        autoFinishArmed = autoEnd

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            phase = .error("Spracherkennung nicht verfügbar")
            throw ListenError.unavailable
        }

        try activateBackgroundAudioSession()

        let bg = UIApplication.shared.applicationState != .active
        // Do not force on-device in background. Logs showed immediate 1110 after
        // background refresh with requiresOnDeviceRecognition=true while mic buffers flowed.
        var preferOnDevice = false

        do {
            try installRecognitionPipeline(preferOnDevice: preferOnDevice, speechRecognizer: speechRecognizer)
        } catch {
            if preferOnDevice {
                VoiceDebugLog.event("VOICE_RECOVERY", "on_device_failed_try_cloud")
                try installRecognitionPipeline(preferOnDevice: false, speechRecognizer: speechRecognizer)
                preferOnDevice = false
            } else {
                throw error
            }
        }
        VoiceDebugLog.event("LISTENING_START", "\(appStateDebugName) onDevice=\(preferOnDevice) \(pipelineDebugSummary())")
        VoiceDebugLog.event("RECOGNITION_STARTED", "\(preferOnDevice ? "on_device" : "cloud") \(pipelineDebugSummary())")
    }

    private func installRecognitionPipeline(
        preferOnDevice: Bool,
        speechRecognizer: SFSpeechRecognizer
    ) throws {
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            throw ListenError.unavailable
        }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation
        recognitionRequest.addsPunctuation = true
        if #available(iOS 17.0, *) {
            recognitionRequest.requiresOnDeviceRecognition = preferOnDevice
        }

        let input = audioEngine.inputNode
        var format = input.outputFormat(forBus: 0)
        if format.sampleRate <= 0 || format.channelCount <= 0 {
            try activateBackgroundAudioSession()
            format = input.outputFormat(forBus: 0)
        }
        guard format.sampleRate > 0, format.channelCount > 0 else {
            phase = .error("Mikrofon nicht bereit")
            throw ListenError.micNotReady
        }
        if inputTapInstalled {
            input.removeTap(onBus: 0)
            inputTapInstalled = false
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            Task { @MainActor in
                self?.processAudio(buffer)
            }
        }
        inputTapInstalled = true

        if !audioEngine.isRunning {
            audioEngine.prepare()
            try audioEngine.start()
        }

        liveTranscript = ""
        lastTranscript = ""
        speechStarted = false
        speechStartAt = nil
        lastVoiceAt = nil
        lastTranscriptChangeAt = nil
        pendingEndCandidateAt = nil
        recognitionStartedAt = Date()
        lastAudioBufferAt = Date()
        audioBufferCount = 0
        phase = .listening
        HapticService.medium()
        startSilenceWatcher()

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                self.handleRecognitionCallback(result: result, error: error)
            }
        }
    }

    private func handleRecognitionCallback(result: SFSpeechRecognitionResult?, error: Error?) {
        guard !isMuted else { return }
        if let result {
            let text = result.bestTranscription.formattedString
            if text != liveTranscript {
                liveTranscript = text
                lastTranscriptChangeAt = Date()
                if !text.isEmpty {
                    speechStarted = true
                }
            }
            if result.isFinal, autoFinishArmed, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emitAutoUtteranceIfNeeded(force: false)
            }
        }
        if let error {
            let ns = error as NSError
            VoiceDebugLog.event("VOICE_ERROR", "speech_error code=\(ns.code) domain=\(ns.domain) \(pipelineDebugSummary())")
            let partial = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !partial.isEmpty, autoFinishArmed,
               (ns.domain == "kAFAssistantErrorDomain" || ns.code == 216 || ns.code == 203) {
                emitAutoUtteranceIfNeeded(force: false)
            }
            // CRITICAL: assistant errors leave a dead task while phase stayed .listening —
            // Island showed 🎙 but no audio was captured until the app was opened again.
            tearDownDeadRecognition(reason: "err_\(ns.code)")
        }
    }

    /// Clear a finished/failed recognition pipeline so health can reopen for real.
    private func tearDownDeadRecognition(reason: String) {
        guard case .listening = phase else { return }
        let keepWarm = sessionActive && UIApplication.shared.applicationState != .active && audioEngine.isRunning
        clearRecognitionPipeline(cancel: true, keepAudioEngineRunning: keepWarm, reason: reason)
        autoFinishArmed = false
        phase = .idle
        VoiceDebugLog.event("RECOGNITION_STOPPED", reason)
        VoiceDebugLog.event("BACKGROUND_RECOVERY", "pipeline_cleared")
    }

    enum ListenError: LocalizedError {
        case micNotReady
        case unavailable
        case muted

        var errorDescription: String? {
            switch self {
            case .micNotReady: return "Mikrofon nicht bereit"
            case .unavailable: return "Spracherkennung nicht verfügbar"
            case .muted: return "Stumm"
            }
        }
    }

    /// True while the mic + recognition pipeline is actually capturing speech.
    var isActivelyListening: Bool {
        guard case .listening = phase else { return false }
        guard !isMuted, autoFinishArmed else { return false }
        return audioEngine.isRunning
            && inputTapInstalled
            && recognitionRequest != nil
            && recognitionTask != nil
            && AVAudioSession.sharedInstance().isInputAvailable
            && isInputFlowing
    }

    func verifyListeningPipeline() -> Bool { isActivelyListening }

    func pipelineDebugSummary() -> String {
        let session = AVAudioSession.sharedInstance()
        let bufferAge = lastAudioBufferAt.map { String(format: "%.1f", Date().timeIntervalSince($0)) } ?? "nil"
        return "app=\(appStateDebugName) phase=\(phaseDebugName) sessionActive=\(sessionActive) engine=\(audioEngine.isRunning) tap=\(inputTapInstalled) request=\(recognitionRequest != nil) task=\(recognitionTask != nil) input=\(session.isInputAvailable) flow=\(isInputFlowing) bufferAge=\(bufferAge) buffers=\(audioBufferCount) tts=\(ttsPlayer.isPlaying || synthesizer.isSpeaking) muted=\(isMuted)"
    }

    private var isInputFlowing: Bool {
        let now = Date()
        if let started = recognitionStartedAt, now.timeIntervalSince(started) < 1.7 {
            return true
        }
        guard let lastAudioBufferAt else { return false }
        return now.timeIntervalSince(lastAudioBufferAt) < 1.7
    }

    private var appStateDebugName: String {
        switch UIApplication.shared.applicationState {
        case .active: return "FOREGROUND"
        case .inactive: return "INACTIVE"
        case .background: return "BACKGROUND"
        @unknown default: return "UNKNOWN"
        }
    }

    private var phaseDebugName: String {
        switch phase {
        case .idle: return "idle"
        case .listening: return "listening"
        case .processing: return "processing"
        case .speaking: return "speaking"
        case .error: return "error"
        }
    }

    /// STT tasks die in background — refresh / reopen so follow-ups still land.
    func refreshRecognitionIfStale(maxAge: TimeInterval = 45) {
        guard !isMuted else { return }
        if case .listening = phase, !isActivelyListening {
            VoiceDebugLog.event("BACKGROUND_RECOVERY", "stale_dead_pipeline \(pipelineDebugSummary())")
            do {
                try hardReinitAudioForListen()
                try startListening(autoEnd: true)
            } catch {
                phase = .idle
                VoiceDebugLog.event("VOICE_ERROR", error.localizedDescription)
            }
            return
        }
        guard case .listening = phase, autoFinishArmed else { return }
        // In background, a healthy running recognition task is more valuable than
        // a proactive refresh. Restarting it caused kAFAssistant 1110 and lost STT.
        guard UIApplication.shared.applicationState == .active else { return }
        let started = recognitionStartedAt ?? .distantPast
        guard Date().timeIntervalSince(started) >= maxAge else { return }
        let partial = liveTranscript
        VoiceDebugLog.event("RECOGNITION_STOPPED", "refresh_age=\(Int(maxAge))")
        do {
            try startListening(autoEnd: true)
            if !partial.isEmpty {
                liveTranscript = partial
                lastTranscript = partial
                speechStarted = true
            }
            VoiceDebugLog.event("RECOGNITION_STARTED", "refreshed")
        } catch {
            phase = .idle
            VoiceDebugLog.event("VOICE_ERROR", error.localizedDescription)
        }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        if muted {
            autoFinishArmed = false
            stopListening(cancel: true)
            if case .listening = phase { phase = .idle }
            liveTranscript = ""
        }
    }

    func stopListening(cancel: Bool = false) {
        clearRecognitionPipeline(cancel: cancel, keepAudioEngineRunning: false, reason: cancel ? "cancel" : "end")
        level = 0
        bands = Array(repeating: 0.1, count: bands.count)
        if case .listening = phase {
            phase = liveTranscript.isEmpty ? .idle : .processing
        }
    }

    private func clearRecognitionPipeline(
        cancel: Bool,
        keepAudioEngineRunning: Bool,
        reason: String
    ) {
        let hadPipeline = recognitionRequest != nil || recognitionTask != nil
        if !hadPipeline {
            if cancel {
                VoiceDebugLog.event("DUPLICATE_CANCEL_IGNORED", reason)
            }
            silenceTask?.cancel()
            silenceTask = nil
            autoFinishArmed = false
            if keepAudioEngineRunning { return }
            if audioEngine.isRunning { audioEngine.stop() }
            if inputTapInstalled {
                audioEngine.inputNode.removeTap(onBus: 0)
                inputTapInstalled = false
            }
            lastAudioBufferAt = nil
            audioBufferCount = 0
            return
        }

        silenceTask?.cancel()
        silenceTask = nil
        VoiceDebugLog.event("RECOGNITION_STOPPED", reason)
        recognitionRequest?.endAudio()
        if cancel {
            recognitionTask?.cancel()
        }
        recognitionRequest = nil
        recognitionTask = nil
        autoFinishArmed = false

        if keepAudioEngineRunning {
            VoiceDebugLog.event("BACKGROUND_RECOVERY", "mic_kept_warm")
            return
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if inputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            inputTapInstalled = false
        }
        lastAudioBufferAt = nil
        audioBufferCount = 0
    }

    private func pauseRecognitionForSessionTTS() {
        VoiceDebugLog.event("VOICE_RECOVERY", "pause_recognition_keep_mic")
        clearRecognitionPipeline(cancel: true, keepAudioEngineRunning: true, reason: "tts_keep_mic_warm")
        do {
            try activateBackgroundAudioSession()
            try ensureWarmInputPipeline()
        } catch {
            VoiceDebugLog.event("VOICE_ERROR", "warm_mic_failed \(error.localizedDescription)")
        }
    }

    private func ensureWarmInputPipeline() throws {
        let input = audioEngine.inputNode
        var format = input.outputFormat(forBus: 0)
        if format.sampleRate <= 0 || format.channelCount <= 0 {
            try activateBackgroundAudioSession()
            format = input.outputFormat(forBus: 0)
        }
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw ListenError.micNotReady
        }
        if !inputTapInstalled {
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
                Task { @MainActor in
                    self?.processAudio(buffer)
                }
            }
            inputTapInstalled = true
        }
        if !audioEngine.isRunning {
            audioEngine.prepare()
            try audioEngine.start()
        }
        if lastAudioBufferAt == nil {
            lastAudioBufferAt = Date()
        }
        VoiceDebugLog.event("MIC_WARM_SESSION", "engine=\(audioEngine.isRunning) tap=\(inputTapInstalled)")
    }

    func finishUtterance() -> String {
        autoFinishArmed = false
        pendingEndCandidateAt = nil
        let keepWarm = sessionActive && audioEngine.isRunning
        clearRecognitionPipeline(
            cancel: false,
            keepAudioEngineRunning: keepWarm,
            reason: keepWarm ? "speech_end_keep_warm" : "speech_end"
        )
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = text.isEmpty ? .idle : .processing
        return text
    }

    func speak(_ text: String, allowBargeIn: Bool = false) {
        speakInternal(text, allowBargeIn: allowBargeIn, notifyWhenFinished: true)
    }

    /// Short mid-turn bridge ("Ich schaue kurz nach") — must not reopen the mic.
    func speakBridge(_ text: String) {
        speakInternal(text, allowBargeIn: false, notifyWhenFinished: false)
    }

    private func speakInternal(_ text: String, allowBargeIn: Bool, notifyWhenFinished: Bool) {
        let natural = NOCOSpeakVoiceSettings.usesNaturalPipeline
        let cleaned = natural
            ? Self.naturalizeForSpeech(Self.cleanForSpeech(text))
            : Self.applyVoiceAIPronunciation(Self.cleanForSpeech(text))
        guard !cleaned.isEmpty else {
            phase = .idle
            if notifyWhenFinished {
                notifySpeakFinishedOnce()
            }
            return
        }

        cancelBargeIn()
        stopSpeaking(notifyFinished: false)
        suppressSpeakFinishedNotify = !notifyWhenFinished
        if sessionActive {
            pauseRecognitionForSessionTTS()
        } else {
            stopListening(cancel: true)
        }

        speakingTextLower = cleaned.lowercased()
        bargeInArmed = allowBargeIn

        do {
            if allowBargeIn {
                try activateBackgroundAudioSession()
            } else {
                try activateLoudPlaybackSession()
            }
        } catch {
            try? activateBackgroundAudioSession()
        }

        let chunks = natural
            ? Self.naturalSpeechChunks(from: cleaned)
            : Self.speechChunks(from: cleaned)
        pendingSpeakChunks = chunks.count
        speakFinishedNotified = false
        speakGeneration &+= 1
        let generation = speakGeneration
        speakingStartedAt = Date()
        ttsUseAmplified = true
        ttsPendingBuffers = 0
        didLogTTSPlaybackStart = false
        speakChunksOrdered = chunks
        revealedSpeakChunkCount = 0
        speakChunkDidReveal = Array(repeating: false, count: chunks.count)
        spokenVisibleText = ""
        phase = .speaking
        HapticService.soft()

        VoiceDebugLog.event("TTS_PREPARED", "chunks=\(chunks.count) chars=\(cleaned.count) bridge=\(!notifyWhenFinished)")
        VoiceDebugLog.event("TTS_START", String(cleaned.prefix(48)))
        Task { await animateSpeakingBands() }
        speakAmplified(chunks: chunks, natural: natural, generation: generation)

        if allowBargeIn {
            scheduleBargeInArming()
        }
    }

    /// If amplified TTS stalls (chunk counters never reach 0), force-finish so mic can reopen.
    func forceFinishIfSpeakingStuck(maxDuration: TimeInterval = 90) {
        guard case .speaking = phase else { return }
        let started = speakingStartedAt ?? .distantPast
        guard Date().timeIntervalSince(started) >= maxDuration else { return }
        stopSpeaking(notifyFinished: true)
    }

    /// Controlled interrupt — finish the current word, then stop.
    func softStopSpeaking(notifyFinished: Bool = true) {
        cancelBargeIn()
        let wasSpeaking = synthesizer.isSpeaking || ttsPlayer.isPlaying || phase == .speaking
        speakGeneration &+= 1
        let generation = speakGeneration
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .word)
        }
        // Amplified buffers: stop after a brief fade window so we don't clip mid-phoneme.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard self.speakGeneration == generation else { return }
            self.stopTTSEngine()
            self.pendingSpeakChunks = 0
            self.ttsUseAmplified = false
            self.speakingStartedAt = nil
            if case .speaking = self.phase {
                self.phase = .idle
            }
            if notifyFinished, wasSpeaking {
                self.notifySpeakFinishedOnce()
            }
        }
    }

    /// Start reading, or stop if already speaking (second tap).
    func toggleSpeak(_ text: String) {
        if case .speaking = phase {
            stopSpeaking(notifyFinished: true)
            HapticService.soft()
            return
        }
        speak(text)
    }

    var isSpeakingNow: Bool {
        if case .speaking = phase { return true }
        return false
    }

    private func speakAmplified(chunks: [String], natural: Bool, generation: UInt64) {
        guard !chunks.isEmpty else {
            phase = .idle
            speakingStartedAt = nil
            notifySpeakFinishedOnce()
            return
        }

        pendingSpeakChunks = chunks.count
        let rate = NOCOSpeakVoiceSettings.resolvedRate(naturalBase: natural)
        let pitch = NOCOSpeakVoiceSettings.resolvedPitch(naturalBase: natural)
        let pre = NOCOSpeakVoiceSettings.resolvedPrePause(naturalBase: natural)
        let post = NOCOSpeakVoiceSettings.resolvedPostPause(naturalBase: natural)
        let inter = NOCOSpeakVoiceSettings.resolvedInterChunkPause(naturalBase: natural)
        let gain = NOCOSpeakVoiceSettings.resolvedGain(naturalBase: natural)
        let voice = bestGermanVoice(preferNatural: natural)

        // Sequential chunks: UI reveal tracks audible playback; pause freezes reveal.
        Task { @MainActor [weak self] in
            guard let self else { return }
            for (index, chunk) in chunks.enumerated() {
                guard self.speakGeneration == generation else { return }
                guard case .speaking = self.phase else { return }
                let ok = await self.playAmplifiedChunk(
                    chunk,
                    index: index,
                    voice: voice,
                    rate: rate,
                    pitch: pitch,
                    pre: index == 0 ? pre : inter,
                    post: post,
                    gain: gain,
                    soft: natural,
                    generation: generation
                )
                guard self.speakGeneration == generation else { return }
                self.pendingSpeakChunks = max(0, self.pendingSpeakChunks - 1)
                if !ok {
                    self.ttsUseAmplified = false
                    self.fallbackSpeak(chunks: Array(chunks[index...]), natural: natural)
                    return
                }
            }
            self.finishAmplifiedIfIdle(generation: generation)
        }
    }

    /// Write one chunk to PCM, reveal progressively as buffers play, wait until done.
    private func playAmplifiedChunk(
        _ chunk: String,
        index: Int,
        voice: AVSpeechSynthesisVoice?,
        rate: Float,
        pitch: Float,
        pre: TimeInterval,
        post: TimeInterval,
        gain: Float,
        soft: Bool,
        generation: UInt64
    ) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let utterance = AVSpeechUtterance(string: chunk)
            utterance.voice = voice
            utterance.rate = rate
            utterance.pitchMultiplier = pitch
            utterance.volume = 1.0
            utterance.preUtteranceDelay = pre
            utterance.postUtteranceDelay = post

            var finishedWrite = false
            var scheduled = 0
            var played = 0
            var resumed = false
            var didStartReveal = false
            func finish(_ ok: Bool) {
                guard !resumed else { return }
                resumed = true
                cont.resume(returning: ok)
            }

            synthesizer.write(utterance) { [weak self] buffer in
                guard let self else {
                    finish(false)
                    return
                }
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }

                if pcm.frameLength == 0 {
                    Task { @MainActor in
                        finishedWrite = true
                        if scheduled == 0 {
                            self.revealSpeakChunk(index, fraction: 1)
                            finish(true)
                            return
                        }
                        if played >= scheduled {
                            self.revealSpeakChunk(index, fraction: 1)
                            finish(true)
                        }
                    }
                    return
                }

                guard let copy = Self.copyPCM(pcm) else { return }
                Self.amplifyPCM(copy, gain: gain, soft: soft)

                Task { @MainActor in
                    guard self.speakGeneration == generation else {
                        finish(false)
                        return
                    }
                    do {
                        try self.ensureTTSEngine(format: copy.format)
                        if !didStartReveal {
                            didStartReveal = true
                            self.revealSpeakChunk(index, fraction: 0.08)
                        }
                        scheduled += 1
                        self.ttsPendingBuffers += 1
                        if !self.ttsPlayer.isPlaying {
                            self.ttsPlayer.play()
                        }
                        if !self.didLogTTSPlaybackStart {
                            self.didLogTTSPlaybackStart = true
                            VoiceDebugLog.event("TTS_PLAYBACK_START", self.pipelineDebugSummary())
                        }
                        self.ttsPlayer.scheduleBuffer(
                            copy,
                            completionCallbackType: .dataPlayedBack
                        ) { [weak self] _ in
                            Task { @MainActor in
                                guard let self else { return }
                                guard self.speakGeneration == generation else { return }
                                played += 1
                                self.ttsPendingBuffers = max(0, self.ttsPendingBuffers - 1)
                                // Progress from buffers actually played (pauses freeze reveal).
                                if self.ttsPlayer.isPlaying || finishedWrite {
                                    let denom = max(scheduled, played, 1)
                                    let frac = min(1, Double(played) / Double(denom))
                                    self.revealSpeakChunk(index, fraction: max(0.08, frac))
                                }
                                if finishedWrite, played >= scheduled {
                                    self.revealSpeakChunk(index, fraction: 1)
                                    finish(true)
                                }
                            }
                        }
                    } catch {
                        finish(false)
                    }
                }
            }
        }
    }

    /// Grow visible transcript with TTS playback (never dump full reply up front).
    private func revealSpeakChunk(_ index: Int, fraction: Double = 1) {
        guard speakChunksOrdered.indices.contains(index) else { return }
        if speakChunkDidReveal.indices.contains(index) {
            speakChunkDidReveal[index] = true
        }
        revealedSpeakChunkCount = max(revealedSpeakChunkCount, index + 1)
        let clamped = min(1, max(0, fraction))
        var parts: [String] = []
        for i in 0..<index {
            parts.append(speakChunksOrdered[i])
        }
        let current = speakChunksOrdered[index]
        if clamped >= 0.999 {
            parts.append(current)
        } else {
            let n = max(1, Int(ceil(Double(current.count) * clamped)))
            parts.append(String(current.prefix(n)))
        }
        spokenVisibleText = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func revealAllSpokenText() {
        let joined = speakChunksOrdered.joined(separator: " ")
        let full = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty {
            spokenVisibleText = full
        }
        revealedSpeakChunkCount = speakChunksOrdered.count
    }

    private func finishAmplifiedIfIdle(generation: UInt64) {
        guard speakGeneration == generation else { return }
        guard ttsUseAmplified, case .speaking = phase else { return }
        if pendingSpeakChunks > 0 || ttsPendingBuffers > 0 { return }
        // `.dataPlayedBack` already means audio left the player. Brief settle for DAC,
        // then confirm the node is idle before tearing the engine down (avoids clipped tails).
        Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<8 {
                try? await Task.sleep(nanoseconds: 40_000_000)
                guard self.speakGeneration == generation else { return }
                guard case .speaking = self.phase else { return }
                if self.pendingSpeakChunks > 0 || self.ttsPendingBuffers > 0 { return }
                if !self.ttsPlayer.isPlaying { break }
            }
            guard self.speakGeneration == generation else { return }
            guard case .speaking = self.phase else { return }
            guard self.pendingSpeakChunks == 0, self.ttsPendingBuffers == 0 else { return }
            self.revealAllSpokenText()
            self.phase = .idle
            self.speakingStartedAt = nil
            HapticService.success()
            // Soft stop: leave engine attached; hard stop only if still marked playing.
            if self.ttsPlayer.isPlaying {
                self.ttsPlayer.pause()
            }
            VoiceDebugLog.event("TTS_PLAYBACK_COMPLETE", self.pipelineDebugSummary())
            self.notifySpeakFinishedOnce()
        }
    }

    private static func copyPCM(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else {
            return nil
        }
        copy.frameLength = source.frameLength
        let channels = Int(source.format.channelCount)
        if let src = source.floatChannelData, let dst = copy.floatChannelData {
            let frames = Int(source.frameLength)
            for ch in 0..<channels {
                memcpy(dst[ch], src[ch], frames * MemoryLayout<Float>.size)
            }
        }
        return copy
    }

    private func fallbackSpeak(chunks: [String], natural: Bool) {
        stopTTSEngine()
        speakChunksOrdered = chunks
        revealedSpeakChunkCount = 0
        speakChunkDidReveal = Array(repeating: false, count: chunks.count)
        spokenVisibleText = ""
        fallbackSpeakChunkCursor = 0
        pendingSpeakChunks = chunks.count
        let rate = NOCOSpeakVoiceSettings.resolvedRate(naturalBase: natural)
        let pitch = NOCOSpeakVoiceSettings.resolvedPitch(naturalBase: natural)
        let pre = NOCOSpeakVoiceSettings.resolvedPrePause(naturalBase: natural)
        let post = NOCOSpeakVoiceSettings.resolvedPostPause(naturalBase: natural)
        let inter = NOCOSpeakVoiceSettings.resolvedInterChunkPause(naturalBase: natural)
        let voice = bestGermanVoice(preferNatural: natural)
        for (index, chunk) in chunks.enumerated() {
            let utterance = AVSpeechUtterance(string: chunk)
            utterance.voice = voice
            utterance.rate = rate
            utterance.pitchMultiplier = pitch
            utterance.volume = 1.0
            utterance.preUtteranceDelay = index == 0 ? pre : inter
            utterance.postUtteranceDelay = post
            // Reveal is driven by willSpeakRange / didStart — not by queueing.
            synthesizer.speak(utterance)
        }
    }

    private func ensureTTSEngine(format: AVAudioFormat) throws {
        if !ttsEngineReady {
            ttsEngine.attach(ttsPlayer)
            ttsEngine.connect(ttsPlayer, to: ttsEngine.mainMixerNode, format: format)
            // Extra headroom on mixer (linear > 1)
            ttsEngine.mainMixerNode.outputVolume = 1.15
            ttsEngineReady = true
        }
        if !ttsEngine.isRunning {
            try ttsEngine.start()
        }
    }

    private func stopTTSEngine() {
        if ttsPlayer.isPlaying {
            ttsPlayer.stop()
        }
        ttsPlayer.reset()
        if ttsEngine.isRunning {
            ttsEngine.stop()
        }
        ttsPendingBuffers = 0
    }

    private static func amplifyPCM(_ buffer: AVAudioPCMBuffer, gain: Float, soft: Bool = false) {
        guard let channels = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        // Soft curve = warmer, less “robot clip”; still loud enough for Speak.
        let curve: Float = soft ? 0.62 : 0.72
        for ch in 0..<channelCount {
            let samples = channels[ch]
            for i in 0..<frames {
                let boosted = samples[i] * gain
                samples[i] = tanh(boosted * curve)
            }
        }
    }

    func stopSpeaking(notifyFinished: Bool = true) {
        cancelBargeIn()
        let wasSpeaking = synthesizer.isSpeaking || ttsPlayer.isPlaying || phase == .speaking
        // Invalidate in-flight amplified buffers so they cannot finish a dead utterance.
        speakGeneration &+= 1
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        stopTTSEngine()
        pendingSpeakChunks = 0
        ttsUseAmplified = false
        speakingTextLower = ""
        speakingStartedAt = nil
        if case .speaking = phase {
            phase = .idle
        }
        if notifyFinished, wasSpeaking {
            notifySpeakFinishedOnce()
        }
    }

    private func notifySpeakFinishedOnce() {
        guard !speakFinishedNotified else { return }
        speakFinishedNotified = true
        if suppressSpeakFinishedNotify {
            suppressSpeakFinishedNotify = false
            VoiceDebugLog.event("TTS_AUDIO_COMPLETE", "bridge_no_resume \(pipelineDebugSummary())")
            return
        }
        VoiceDebugLog.event("TTS_AUDIO_COMPLETE", "notify \(pipelineDebugSummary())")
        onSpeakFinished?()
    }

    func availableGermanVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("de") }
            .sorted { voiceScore($0) > voiceScore($1) }
    }

    // MARK: - Silence detection

    private func startSilenceWatcher() {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                await MainActor.run {
                    self?.emitAutoUtteranceIfNeeded(force: false)
                }
            }
        }
    }

    private func emitAutoUtteranceIfNeeded(force: Bool) {
        guard !isMuted else { return }
        guard autoFinishArmed else { return }

        // Barge-in path while TTS is playing.
        if case .speaking = phase, bargeInArmed {
            emitBargeInIfNeeded()
            return
        }

        guard case .listening = phase else { return }
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { return }
        // Ignore lone hesitations so Island sessions don't "send" noise.
        let hesitation = Set(["äh", "ähm", "hm", "hmm", "mhm", "öh", "öhä", "em", "erm"])
        if hesitation.contains(text.lowercased()) { return }

        // Transcript alone is enough to mark that the user spoke
        if !speechStarted {
            speechStarted = true
            if speechStartAt == nil { speechStartAt = Date() }
        }

        let now = Date()
        let lastActivity = max(lastVoiceAt ?? .distantPast, lastTranscriptChangeAt ?? .distantPast)
        let quietFor = now.timeIntervalSince(lastActivity)
        let transcriptStable = lastTranscriptChangeAt.map { now.timeIntervalSince($0) >= transcriptStableToEnd } ?? false
        let spokenLongEnough = speechStartAt.map { now.timeIntervalSince($0) >= minSpeechSeconds } ?? false

        // Punctuation / clear end → send sooner.
        let endsClean = text.hasSuffix(".") || text.hasSuffix("!") || text.hasSuffix("?") || text.hasSuffix("…")
        let adaptiveSilence = endsClean ? max(0.55, silenceToEnd * 0.72) : silenceToEnd
        let adaptiveNatural = endsClean ? max(0.48, naturalEndQuiet * 0.75) : naturalEndQuiet

        // Background: slightly shorter silence so Island follow-ups don't feel stuck.
        let bg = UIApplication.shared.applicationState != .active
        let silenceScale = bg ? 0.82 : 1.0
        let silenceReady = quietFor >= adaptiveSilence * silenceScale
        let naturalEnd = spokenLongEnough && transcriptStable && quietFor >= adaptiveNatural * silenceScale
        let longSilenceFallback = spokenLongEnough && quietFor >= adaptiveSilence * 1.2 * silenceScale
        // `force` kept for API compat — still requires a real quiet beat.
        let softForce = force && spokenLongEnough && transcriptStable && quietFor >= 0.9
        let candidate = softForce || naturalEnd || (transcriptStable && silenceReady) || longSilenceFallback

        guard candidate else {
            pendingEndCandidateAt = nil
            return
        }

        // Confirm the pause sticks (user may still be thinking).
        let confirmNeeded = endsClean ? max(0.12, endConfirmGrace * 0.7) : endConfirmGrace
        if let started = pendingEndCandidateAt {
            if quietFor < 0.4 {
                pendingEndCandidateAt = nil
                return
            }
            guard now.timeIntervalSince(started) >= confirmNeeded else { return }
        } else {
            pendingEndCandidateAt = now
            return
        }

        pendingEndCandidateAt = nil
        autoFinishArmed = false
        let finished = finishUtterance()
        guard !finished.isEmpty else {
            // Empty recognition — keep listening instead of hanging in processing.
            VoiceDebugLog.event("SPEECH_END", "empty")
            autoFinishArmed = true
            if case .processing = phase { phase = .listening }
            do {
                try activateListeningAfterTTS()
                try startListening(autoEnd: true)
            } catch {
                phase = .error(error.localizedDescription)
            }
            return
        }
        VoiceDebugLog.event("SPEECH_DETECTED", String(finished.prefix(48)))
        HapticService.selection()
        onAutoUtterance?(finished)
    }

    private func emitBargeInIfNeeded() {
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3 else { return }
        let lower = text.lowercased()
        // Ignore TTS echo leaking into the mic.
        if !speakingTextLower.isEmpty, speakingTextLower.contains(lower) || lower.count >= 8 && speakingTextLower.contains(String(lower.prefix(8))) {
            return
        }
        let now = Date()
        let lastActivity = max(lastVoiceAt ?? .distantPast, lastTranscriptChangeAt ?? .distantPast)
        let quietFor = now.timeIntervalSince(lastActivity)
        let spokenLongEnough = speechStartAt.map { now.timeIntervalSince($0) >= 0.55 } ?? false
        let stable = lastTranscriptChangeAt.map { now.timeIntervalSince($0) >= 0.45 } ?? false
        // Need clear user speech + a solid pause so we don't cut TTS mid-sentence.
        guard spokenLongEnough, stable, quietFor >= 0.55 else { return }

        autoFinishArmed = false
        bargeInArmed = false
        cancelBargeInListenOnly()
        let captured = text
        softStopSpeaking(notifyFinished: false)
        liveTranscript = ""
        HapticService.selection()
        onBargeIn?(captured)
    }

    private func scheduleBargeInArming() {
        bargeInTask?.cancel()
        bargeInTask = Task { [weak self] in
            // Longer settle so TTS is not clipped by echo / partial self-hearing.
            try? await Task.sleep(nanoseconds: 1_450_000_000)
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                guard case .speaking = self.phase, self.bargeInArmed else { return }
                self.startBargeInListening()
            }
        }
    }

    private func startBargeInListening() {
        guard bargeInArmed, case .speaking = phase, !isMuted else { return }
        do {
            try activateBackgroundAudioSession()
        } catch {
            return
        }
        // Lightweight listen without killing TTS engine.
        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest, let speechRecognizer, speechRecognizer.isAvailable else { return }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation
        recognitionRequest.addsPunctuation = true

        liveTranscript = ""
        speechStarted = false
        speechStartAt = nil
        lastVoiceAt = nil
        lastTranscriptChangeAt = nil
        pendingEndCandidateAt = nil
        autoFinishArmed = true

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        if !audioEngine.isRunning {
            if inputTapInstalled {
                input.removeTap(onBus: 0)
                inputTapInstalled = false
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
                Task { @MainActor in
                    self?.processAudio(buffer)
                }
            }
            inputTapInstalled = true
            do {
                audioEngine.prepare()
                try audioEngine.start()
            } catch {
                return
            }
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.bargeInArmed, case .speaking = self.phase else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if text != self.liveTranscript {
                        self.liveTranscript = text
                        self.lastTranscriptChangeAt = Date()
                        if !text.isEmpty { self.speechStarted = true }
                    }
                    self.emitBargeInIfNeeded()
                }
            }
        }
        startSilenceWatcher()
    }

    private func cancelBargeInListenOnly() {
        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask = nil
        if audioEngine.isRunning {
            // Keep TTS engine separate — only stop input tap if we installed it for barge-in.
            // Full stopListening would kill session; here just detach recognition.
            if inputTapInstalled {
                audioEngine.inputNode.removeTap(onBus: 0)
                inputTapInstalled = false
            }
            audioEngine.stop()
        }
    }

    private func cancelBargeIn() {
        bargeInArmed = false
        bargeInTask?.cancel()
        bargeInTask = nil
        speakingTextLower = ""
    }

    private func processAudio(_ buffer: AVAudioPCMBuffer) {
        guard !isMuted else { return }
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        lastAudioBufferAt = Date()
        audioBufferCount &+= 1

        var sum: Float = 0
        for i in 0..<frames {
            let v = channel[i]
            sum += v * v
        }
        let rms = CGFloat(sqrt(sum / Float(frames)))
        // Stronger gain so the Speak stage reacts clearly to speech volume.
        let boosted = min(rms * 16, 1)
        level = level * 0.35 + boosted * 0.65

        if !speechStarted {
            noiseFloor = noiseFloor * 0.95 + level * 0.05
        }
        let speechThreshold = max(0.035, noiseFloor * speechLevelFactor)

        if level > speechThreshold {
            if !speechStarted {
                speechStarted = true
                speechStartAt = Date()
            }
            lastVoiceAt = Date()
        }

        let bandCount = bands.count
        let slice = max(frames / bandCount, 1)
        var next = bands
        for b in 0..<bandCount {
            let start = b * slice
            let end = min(start + slice, frames)
            guard end > start else { continue }
            var s: Float = 0
            for i in start..<end {
                let v = channel[i]
                s += v * v
            }
            let bandRms = CGFloat(sqrt(s / Float(end - start)))
            let value = min(bandRms * (18 + CGFloat(b) * 0.45), 1)
            next[b] = next[b] * 0.28 + value * 0.72
        }
        bands = next
    }

    private func animateSpeakingBands() async {
        while case .speaking = phase, !Task.isCancelled {
            var next = bands
            for i in 0..<next.count {
                let wave = abs(sin(Date().timeIntervalSinceReferenceDate * 9 + Double(i) * 0.55))
                next[i] = CGFloat(0.25 + wave * 0.75)
            }
            bands = next
            level = next.reduce(0, +) / CGFloat(next.count)
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func bestGermanVoice(preferNatural: Bool = false) -> AVSpeechSynthesisVoice? {
        let voices = availableGermanVoices()
        let id = preferredVoiceIdentifier

        // Explicit system voice (not Natural / Automatic).
        if id != NOCOSpeakVoiceID.natural,
           !id.isEmpty,
           let preferred = voices.first(where: { $0.identifier == id }) {
            return preferred
        }

        // NOCO Natural Voice / Automatic: pick best on-device neural/premium German voice.
        let ranked = voices.sorted {
            naturalVoiceScore($0, boostNatural: preferNatural || id == NOCOSpeakVoiceID.natural)
                > naturalVoiceScore($1, boostNatural: preferNatural || id == NOCOSpeakVoiceID.natural)
        }
        return ranked.first ?? AVSpeechSynthesisVoice(language: "de-DE")
    }

    private func voiceScore(_ voice: AVSpeechSynthesisVoice) -> Int {
        naturalVoiceScore(voice, boostNatural: false)
    }

    private func naturalVoiceScore(_ voice: AVSpeechSynthesisVoice, boostNatural: Bool) -> Int {
        var score = 0
        switch voice.quality {
        case .premium: score += boostNatural ? 14 : 8
        case .enhanced: score += boostNatural ? 9 : 5
        default: score += 1
        }
        if voice.language.lowercased().hasPrefix("de-de") { score += 3 }
        let name = voice.name.lowercased()
        // Prefer clear, modern German neural voices — avoid defaulting to deep male.
        let preferred = ["anna", "helena", "petra", "viktoria", "katja", "shelley", "sandy", "martha", "nicky"]
        let deepMale = ["martin", "markus", "yannick", "stefan", "reed", "thomas"]
        if preferred.contains(where: { name.contains($0) }) {
            score += boostNatural ? 8 : 3
        }
        if deepMale.contains(where: { name.contains($0) }) {
            score -= boostNatural ? 4 : 1
        }
        if name.contains("neural") || name.contains("siri") || name.contains("premium") || name.contains("enhanced") {
            score += boostNatural ? 5 : 2
        }
        if boostNatural, voice.quality == .default {
            score -= 3
        }
        return score
    }

    static func cleanForSpeech(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: #"```[\s\S]*?```"#, with: " Codeblock. ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"`[^`]+`"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\*\*|__|~~|#{1,6}\s*"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^\s*[-*•]\s+"#, with: "", options: [.regularExpression])
        s = s.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        if s.count > 1200 {
            s = String(s.prefix(1200)) + "…"
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func speechChunks(from text: String) -> [String] {
        let parts = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.isEmpty { return [text] }
        var result: [String] = []
        var current = ""
        for part in parts {
            let next = current.isEmpty ? part : current + ". " + part
            if next.count > 180, !current.isEmpty {
                result.append(current.hasSuffix(".") ? current : current + ".")
                current = part
            } else {
                current = next
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Light prosody prep — keeps latency low (no network / no heavy models).
    static func naturalizeForSpeech(_ text: String) -> String {
        var s = text
        // Soften list markers into spoken rhythm.
        s = s.replacingOccurrences(of: #"^\s*\d+\.\s+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: " z.B. ", with: " zum Beispiel ", options: .caseInsensitive)
        s = s.replacingOccurrences(of: " z. B. ", with: " zum Beispiel ", options: .caseInsensitive)
        s = s.replacingOccurrences(of: " usw.", with: " und so weiter", options: .caseInsensitive)
        s = s.replacingOccurrences(of: " etc.", with: " und so weiter", options: .caseInsensitive)
        // Gentle breath after commas / dashes without inventing words.
        s = s.replacingOccurrences(of: #"\s+[–—-]\s+"#, with: ", ", options: .regularExpression)
        // English product name — German TTS should say "Voice A I", not "Voiz Ei".
        s = applyVoiceAIPronunciation(s)
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Force English-style letter pronunciation for "Voice AI" inside German TTS.
    static func applyVoiceAIPronunciation(_ text: String) -> String {
        var s = text
        let replacements: [(String, String)] = [
            ("NOCO Voice AI", "NOCO Voice A I"),
            ("noco voice ai", "NOCO Voice A I"),
            ("Voice AI", "Voice A I"),
            ("voice ai", "Voice A I"),
            ("Voice-AI", "Voice A I"),
            ("voice-ai", "Voice A I")
        ]
        for (from, to) in replacements {
            s = s.replacingOccurrences(of: from, with: to, options: from.first?.isUppercase == true ? [] : .caseInsensitive)
        }
        // Catch remaining case variants via regex.
        s = s.replacingOccurrences(
            of: #"(?i)\bvoice[\s\-]?ai\b"#,
            with: "Voice A I",
            options: .regularExpression
        )
        return s
    }

    /// Slightly shorter phrases than default → more natural pauses, still quick to start.
    static func naturalSpeechChunks(from text: String) -> [String] {
        let rough = text
            .replacingOccurrences(of: ";", with: ".")
            .replacingOccurrences(of: ":", with: ",")
        let sentenceParts = rough.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if sentenceParts.isEmpty { return speechChunks(from: text) }

        var result: [String] = []
        for sentence in sentenceParts {
            let commas = sentence.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if commas.count <= 1 || sentence.count < 90 {
                let ended = sentence.hasSuffix(".") ? sentence : sentence + "."
                result.append(ended)
                continue
            }
            var current = ""
            for (i, part) in commas.enumerated() {
                let piece = current.isEmpty ? part : current + ", " + part
                if piece.count > 110, !current.isEmpty {
                    result.append(current + ",")
                    current = part
                } else {
                    current = piece
                }
                if i == commas.count - 1, !current.isEmpty {
                    result.append(current.hasSuffix(".") ? current : current + ".")
                }
            }
        }
        return result.isEmpty ? speechChunks(from: text) : result
    }

    static func speakPrompt(_ userText: String, depth: AIMode = .flash, style: SpeakStyleHints = SpeakStyleHints()) -> String {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = ["[NOCO SPEAK]"]
        if depth == .think || style.prefersDepth {
            lines.append("Gründliche, klare gesprochene Antwort auf Deutsch. Strukturiert, aber noch gut hörbar — keine endlosen Aufsätze.")
        } else {
            lines.append("Kurze gesprochene Antwort auf Deutsch. Direkt, klar, 1–4 Sätze. Keine Meta-Kommentare.")
        }
        if style.shorter { lines.append("Halte dich besonders kurz.") }
        if style.longer { lines.append("Erkläre etwas ausführlicher, bleib aber sprechbar.") }
        if style.creative { lines.append("Sei kreativ und originell.") }
        if style.professional { lines.append("Ton: professionell, präzise, ohne Floskeln.") }
        if style.highQuality { lines.append("Priorisiere Qualität und Klarheit.") }
        lines.append("Nutzer: \(trimmed)")
        return lines.joined(separator: "\n")
    }

    static func voiceOnlyPrompt(_ userText: String) -> String {
        speakPrompt(userText, depth: .flash)
    }

    static func stripSpeakEcho(_ reply: String) -> String {
        var lines = reply
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let junk = [
            "speak-modus", "nur sprache", "gesprochene antwort", "keine bilder",
            "bildprompts", "galerie-aktionen", "tool-aufrufe", "nutzer:",
            "antworte ausschließlich", "halte dich kurz", "[speak"
        ]
        lines.removeAll { line in
            let lower = line.lowercased()
            return junk.contains(where: { lower.contains($0) })
        }

        var text = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: #"^(antwort|answer)\s*:\s*"#, options: [.regularExpression, .caseInsensitive]) {
            text = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}

extension VoiceService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard !self.ttsUseAmplified else { return }
            if let idx = self.speakChunksOrdered.firstIndex(of: utterance.speechString) {
                self.fallbackSpeakChunkCursor = idx
            }
            self.revealSpeakChunk(self.fallbackSpeakChunkCursor, fraction: 0.05)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            guard !self.ttsUseAmplified else { return }
            guard case .speaking = self.phase else { return }
            let full = utterance.speechString as NSString
            let end = min(full.length, characterRange.location + characterRange.length)
            let frac = full.length > 0 ? Double(end) / Double(full.length) : 1
            if let idx = self.speakChunksOrdered.firstIndex(of: utterance.speechString) {
                self.fallbackSpeakChunkCursor = idx
                self.revealSpeakChunk(idx, fraction: max(0.05, frac))
            } else {
                self.revealSpeakChunk(self.fallbackSpeakChunkCursor, fraction: max(0.05, frac))
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // Amplified path finishes via buffer completions
            guard !self.ttsUseAmplified else { return }
            if let idx = self.speakChunksOrdered.firstIndex(of: utterance.speechString) {
                self.revealSpeakChunk(idx, fraction: 1)
            }
            if !synthesizer.isSpeaking {
                self.revealAllSpokenText()
                self.phase = .idle
                self.speakingStartedAt = nil
                HapticService.success()
                VoiceDebugLog.event("TTS_PLAYBACK_COMPLETE", self.pipelineDebugSummary())
                self.notifySpeakFinishedOnce()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if case .speaking = self.phase {
                self.phase = .idle
            }
        }
    }
}
