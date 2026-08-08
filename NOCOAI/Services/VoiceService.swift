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

    /// Amplified TTS path (gain > 1.0 — AVSpeechUtterance.volume alone caps at 1).
    private let ttsEngine = AVAudioEngine()
    private let ttsPlayer = AVAudioPlayerNode()
    private var ttsEngineReady = false
    private var ttsUseAmplified = false
    private var ttsPendingBuffers = 0

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
            if case .listening = phase {
                stopListening(cancel: true)
                phase = .idle
            }
        case .ended:
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
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
        )
        try session.overrideOutputAudioPort(.speaker)
        try session.setActive(true, options: [])
    }

    /// Loud TTS route — during an active Speak session keep duplex so background mic survives.
    func activateLoudPlaybackSession() throws {
        let session = AVAudioSession.sharedInstance()
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
    }

    /// Back to mic after TTS — never fully deactivate (that suspends background Voice AI).
    func activateListeningAfterTTS() throws {
        let session = AVAudioSession.sharedInstance()
        // Soft route flip only — `setActive(false)` drops UIBackgroundModes.audio keep-alive.
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
        )
        try session.overrideOutputAudioPort(.speaker)
        try session.setActive(true, options: [])
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
        stopListening(cancel: true)
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
        stopListening(cancel: true)
        autoFinishArmed = autoEnd

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            phase = .error("Spracherkennung nicht verfügbar")
            throw ListenError.unavailable
        }

        try activateBackgroundAudioSession()

        let bg = UIApplication.shared.applicationState != .active
        // Prefer on-device in background (cloud STT often dies when suspended).
        var preferOnDevice = false
        if #available(iOS 17.0, *) {
            preferOnDevice = bg && speechRecognizer.supportsOnDeviceRecognition
        }

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
        VoiceDebugLog.event("LISTENING_START", bg ? "background onDevice=\(preferOnDevice)" : "foreground")
        VoiceDebugLog.event("RECOGNITION_STARTED", preferOnDevice ? "on_device" : "cloud")
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
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            Task { @MainActor in
                self?.processAudio(buffer)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()

        liveTranscript = ""
        lastTranscript = ""
        speechStarted = false
        speechStartAt = nil
        lastVoiceAt = nil
        lastTranscriptChangeAt = nil
        pendingEndCandidateAt = nil
        recognitionStartedAt = Date()
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
        silenceTask?.cancel()
        silenceTask = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
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
        return audioEngine.isRunning && recognitionRequest != nil && recognitionTask != nil
    }

    func verifyListeningPipeline() -> Bool { isActivelyListening }

    /// STT tasks die in background — refresh / reopen so follow-ups still land.
    func refreshRecognitionIfStale(maxAge: TimeInterval = 45) {
        guard !isMuted else { return }
        if case .listening = phase, !isActivelyListening {
            VoiceDebugLog.event("BACKGROUND_RECOVERY", "stale_dead_pipeline")
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
        silenceTask?.cancel()
        silenceTask = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        if cancel {
            recognitionTask?.cancel()
        }
        recognitionRequest = nil
        recognitionTask = nil
        level = 0
        bands = Array(repeating: 0.1, count: bands.count)
        if case .listening = phase {
            phase = liveTranscript.isEmpty ? .idle : .processing
        }
    }

    func finishUtterance() -> String {
        autoFinishArmed = false
        pendingEndCandidateAt = nil
        stopListening(cancel: false)
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = text.isEmpty ? .idle : .processing
        return text
    }

    func speak(_ text: String, allowBargeIn: Bool = false) {
        let natural = NOCOSpeakVoiceSettings.usesNaturalPipeline
        let cleaned = natural
            ? Self.naturalizeForSpeech(Self.cleanForSpeech(text))
            : Self.applyVoiceAIPronunciation(Self.cleanForSpeech(text))
        guard !cleaned.isEmpty else {
            phase = .idle
            notifySpeakFinishedOnce()
            return
        }

        cancelBargeIn()
        stopSpeaking(notifyFinished: false)
        stopListening(cancel: true)

        speakingTextLower = cleaned.lowercased()
        bargeInArmed = allowBargeIn

        do {
            // playAndRecord when barge-in needed so mic can hear the user mid-reply.
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
        phase = .speaking
        HapticService.soft()

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

        for (index, chunk) in chunks.enumerated() {
            let utterance = AVSpeechUtterance(string: chunk)
            utterance.voice = voice
            utterance.rate = rate
            utterance.pitchMultiplier = pitch
            utterance.volume = 1.0
            utterance.preUtteranceDelay = index == 0 ? pre : inter
            utterance.postUtteranceDelay = post

            synthesizer.write(utterance) { [weak self] buffer in
                guard let self else { return }
                // Buffer is only valid inside this callback — copy immediately.
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }

                if pcm.frameLength == 0 {
                    Task { @MainActor in
                        guard self.speakGeneration == generation else { return }
                        self.pendingSpeakChunks = max(0, self.pendingSpeakChunks - 1)
                        self.finishAmplifiedIfIdle(generation: generation)
                    }
                    return
                }

                guard let copy = Self.copyPCM(pcm) else { return }
                Self.amplifyPCM(copy, gain: gain, soft: natural)

                Task { @MainActor in
                    guard self.speakGeneration == generation else { return }
                    do {
                        try self.ensureTTSEngine(format: copy.format)
                        self.ttsPendingBuffers += 1
                        if !self.ttsPlayer.isPlaying {
                            self.ttsPlayer.play()
                        }
                        self.ttsPlayer.scheduleBuffer(copy, completionHandler: { [weak self] in
                            Task { @MainActor in
                                guard let self else { return }
                                guard self.speakGeneration == generation else { return }
                                self.ttsPendingBuffers = max(0, self.ttsPendingBuffers - 1)
                                self.finishAmplifiedIfIdle(generation: generation)
                            }
                        })
                    } catch {
                        guard self.speakGeneration == generation else { return }
                        self.ttsUseAmplified = false
                        self.fallbackSpeak(chunks: chunks, natural: natural)
                    }
                }
            }
        }
    }

    private func finishAmplifiedIfIdle(generation: UInt64) {
        guard speakGeneration == generation else { return }
        guard ttsUseAmplified, case .speaking = phase else { return }
        if pendingSpeakChunks > 0 || ttsPendingBuffers > 0 { return }
        // Empty-buffer race: chunk counter can hit 0 before the last PCM is scheduled.
        // Defer completion until playback is truly idle.
        Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<8 {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard self.speakGeneration == generation else { return }
                guard case .speaking = self.phase else { return }
                if self.pendingSpeakChunks > 0 || self.ttsPendingBuffers > 0 || self.ttsPlayer.isPlaying {
                    continue
                }
                // One extra settle so the last syllable isn't cut.
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard self.speakGeneration == generation else { return }
                guard case .speaking = self.phase else { return }
                if self.pendingSpeakChunks > 0 || self.ttsPendingBuffers > 0 || self.ttsPlayer.isPlaying {
                    continue
                }
                self.phase = .idle
                self.speakingStartedAt = nil
                HapticService.success()
                self.stopTTSEngine()
                VoiceDebugLog.event("TTS_AUDIO_COMPLETE")
                self.notifySpeakFinishedOnce()
                return
            }
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
        VoiceDebugLog.event("TTS_AUDIO_COMPLETE", "notify")
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
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
                Task { @MainActor in
                    self?.processAudio(buffer)
                }
            }
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
            audioEngine.inputNode.removeTap(onBus: 0)
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
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // Amplified path finishes via buffer completions
            guard !self.ttsUseAmplified else { return }
            if !synthesizer.isSpeaking {
                self.phase = .idle
                self.speakingStartedAt = nil
                HapticService.success()
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
