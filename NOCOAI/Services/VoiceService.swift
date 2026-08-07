import AVFoundation
import Foundation
import Speech

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

    /// Amplified TTS path (gain > 1.0 — AVSpeechUtterance.volume alone caps at 1).
    private let ttsEngine = AVAudioEngine()
    private let ttsPlayer = AVAudioPlayerNode()
    private var ttsEngineReady = false
    private var ttsUseAmplified = false
    private var ttsPendingBuffers = 0

    /// Wait for a clear end of speech — finish mid-thought, then Flash answers fast.
    private let silenceToEnd: TimeInterval = 1.85
    private let transcriptStableToEnd: TimeInterval = 1.25
    private let minSpeechSeconds: TimeInterval = 0.6
    private let naturalEndQuiet: TimeInterval = 1.45
    private let endConfirmGrace: TimeInterval = 0.35
    private let speechLevelFactor: CGFloat = 2.5

    private var pendingEndCandidateAt: Date?

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
            mode: .measurement,
            options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
        )
        try session.overrideOutputAudioPort(.speaker)
        try session.setActive(true, options: [])
    }

    /// Loud TTS route — pure playback is louder than playAndRecord; force speaker.
    func activateLoudPlaybackSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.defaultToSpeaker, .allowBluetoothA2DP]
        )
        try session.overrideOutputAudioPort(.speaker)
        try session.setActive(true, options: [])
    }

    /// Back to mic after TTS — deactivate first so route switches cleanly.
    func activateListeningAfterTTS() throws {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
        )
        try session.overrideOutputAudioPort(.speaker)
        try session.setActive(true, options: [])
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

    func startListening(autoEnd: Bool = true) throws {
        guard !isMuted else {
            phase = .idle
            return
        }
        stopSpeaking(notifyFinished: false)
        stopListening(cancel: true)
        autoFinishArmed = autoEnd

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            phase = .error("Spracherkennung nicht verfügbar")
            return
        }

        try activateBackgroundAudioSession()

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation
        recognitionRequest.addsPunctuation = true
        if #available(iOS 17.0, *) {
            recognitionRequest.requiresOnDeviceRecognition = false
        }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            phase = .error("Mikrofon nicht bereit")
            return
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
        phase = .listening
        HapticService.medium()
        startSilenceWatcher()

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                guard !self.isMuted else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if text != self.liveTranscript {
                        self.liveTranscript = text
                        self.lastTranscriptChangeAt = Date()
                        if !text.isEmpty {
                            self.speechStarted = true
                        }
                    }
                    if result.isFinal, self.autoFinishArmed, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Soft hint only — never cut mid-thought on Apple's isFinal.
                        self.emitAutoUtteranceIfNeeded(force: false)
                    }
                }
                if let error {
                    let ns = error as NSError
                    if ns.domain == "kAFAssistantErrorDomain" || ns.code == 216 || ns.code == 203 {
                        // Soft recognition end — timers decide, don't force-send.
                        if self.autoFinishArmed,
                           !self.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            self.emitAutoUtteranceIfNeeded(force: false)
                        }
                        return
                    }
                    if case .listening = self.phase {
                        let partial = self.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !partial.isEmpty, self.autoFinishArmed {
                            self.emitAutoUtteranceIfNeeded(force: false)
                        }
                        // else: keep listening — don't kill the session on soft errors
                    }
                }
            }
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

    func speak(_ text: String) {
        let natural = NOCOSpeakVoiceSettings.usesNaturalPipeline
        let cleaned = natural
            ? Self.naturalizeForSpeech(Self.cleanForSpeech(text))
            : Self.cleanForSpeech(text)
        guard !cleaned.isEmpty else {
            phase = .idle
            notifySpeakFinishedOnce()
            return
        }

        stopSpeaking(notifyFinished: false)
        stopListening(cancel: true)

        do {
            try activateLoudPlaybackSession()
        } catch {
            try? activateBackgroundAudioSession()
        }

        let chunks = natural
            ? Self.naturalSpeechChunks(from: cleaned)
            : Self.speechChunks(from: cleaned)
        pendingSpeakChunks = chunks.count
        speakFinishedNotified = false
        ttsUseAmplified = true
        ttsPendingBuffers = 0
        phase = .speaking
        HapticService.soft()

        Task { await animateSpeakingBands() }

        // Amplified path: write PCM → gain → AVAudioEngine (utterance.volume alone is capped at 1.0)
        speakAmplified(chunks: chunks, natural: natural)
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

    private func speakAmplified(chunks: [String], natural: Bool) {
        guard !chunks.isEmpty else {
            phase = .idle
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
                        self.pendingSpeakChunks = max(0, self.pendingSpeakChunks - 1)
                        self.finishAmplifiedIfIdle()
                    }
                    return
                }

                guard let copy = Self.copyPCM(pcm) else { return }
                Self.amplifyPCM(copy, gain: gain, soft: natural)

                Task { @MainActor in
                    do {
                        try self.ensureTTSEngine(format: copy.format)
                        self.ttsPendingBuffers += 1
                        if !self.ttsPlayer.isPlaying {
                            self.ttsPlayer.play()
                        }
                        self.ttsPlayer.scheduleBuffer(copy, completionHandler: { [weak self] in
                            Task { @MainActor in
                                guard let self else { return }
                                self.ttsPendingBuffers = max(0, self.ttsPendingBuffers - 1)
                                self.finishAmplifiedIfIdle()
                            }
                        })
                    } catch {
                        self.ttsUseAmplified = false
                        self.fallbackSpeak(chunks: chunks, natural: natural)
                    }
                }
            }
        }
    }

    private func finishAmplifiedIfIdle() {
        guard ttsUseAmplified, case .speaking = phase else { return }
        if pendingSpeakChunks > 0 || ttsPendingBuffers > 0 { return }
        phase = .idle
        HapticService.success()
        stopTTSEngine()
        notifySpeakFinishedOnce()
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
        let wasSpeaking = synthesizer.isSpeaking || ttsPlayer.isPlaying || phase == .speaking
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        stopTTSEngine()
        pendingSpeakChunks = 0
        ttsUseAmplified = false
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
        guard autoFinishArmed, case .listening = phase else { return }
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { return }

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

        // Prefer clear pause after speech; never rush mid-thought.
        let silenceReady = quietFor >= silenceToEnd
        let naturalEnd = spokenLongEnough && transcriptStable && quietFor >= naturalEndQuiet
        let longSilenceFallback = spokenLongEnough && quietFor >= silenceToEnd * 1.15
        // `force` kept for API compat — still requires a real quiet beat.
        let softForce = force && spokenLongEnough && transcriptStable && quietFor >= 1.2
        let candidate = softForce || naturalEnd || (transcriptStable && silenceReady) || longSilenceFallback

        guard candidate else {
            pendingEndCandidateAt = nil
            return
        }

        // Confirm the pause sticks (user may still be thinking).
        if let started = pendingEndCandidateAt {
            if quietFor < 0.55 {
                pendingEndCandidateAt = nil
                return
            }
            guard now.timeIntervalSince(started) >= endConfirmGrace else { return }
        } else {
            pendingEndCandidateAt = now
            return
        }

        pendingEndCandidateAt = nil
        autoFinishArmed = false
        let finished = finishUtterance()
        guard !finished.isEmpty else { return }
        HapticService.selection()
        onAutoUtterance?(finished)
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
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
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
