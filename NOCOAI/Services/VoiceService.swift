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
    private let ttsGain: Float = 8.5

    /// Quiet after speech / transcript pause before auto-send (fast).
    private let silenceToEnd: TimeInterval = 0.55
    private let transcriptStableToEnd: TimeInterval = 0.50
    private let minSpeechSeconds: TimeInterval = 0.22
    private let speechLevelFactor: CGFloat = 2.6

    var preferredVoiceIdentifier: String {
        get { UserDefaults.standard.string(forKey: "nocoai.voiceId") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "nocoai.voiceId") }
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
                        self.emitAutoUtteranceIfNeeded(force: true)
                    }
                }
                if let error {
                    let ns = error as NSError
                    if ns.domain == "kAFAssistantErrorDomain" || ns.code == 216 || ns.code == 203 {
                        // Often fires when recognition ends — if we have text, send it
                        if self.autoFinishArmed,
                           !self.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            self.emitAutoUtteranceIfNeeded(force: true)
                        }
                        return
                    }
                    if case .listening = self.phase {
                        let partial = self.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !partial.isEmpty, self.autoFinishArmed {
                            self.emitAutoUtteranceIfNeeded(force: true)
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
        stopListening(cancel: false)
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = text.isEmpty ? .idle : .processing
        return text
    }

    func speak(_ text: String) {
        let cleaned = Self.cleanForSpeech(text)
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

        let chunks = Self.speechChunks(from: cleaned)
        pendingSpeakChunks = chunks.count
        speakFinishedNotified = false
        ttsUseAmplified = true
        ttsPendingBuffers = 0
        phase = .speaking
        HapticService.soft()

        Task { await animateSpeakingBands() }

        // Amplified path: write PCM → gain → AVAudioEngine (utterance.volume alone is capped at 1.0)
        speakAmplified(chunks: chunks)
    }

    private func speakAmplified(chunks: [String]) {
        guard !chunks.isEmpty else {
            phase = .idle
            notifySpeakFinishedOnce()
            return
        }

        pendingSpeakChunks = chunks.count

        for (index, chunk) in chunks.enumerated() {
            let utterance = AVSpeechUtterance(string: chunk)
            utterance.voice = bestGermanVoice()
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.94
            utterance.pitchMultiplier = 1.02
            utterance.volume = 1.0
            utterance.preUtteranceDelay = index == 0 ? 0 : 0.04
            utterance.postUtteranceDelay = 0

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
                Self.amplifyPCM(copy, gain: self.ttsGain)

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
                        self.fallbackSpeak(chunks: chunks)
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

    private func fallbackSpeak(chunks: [String]) {
        stopTTSEngine()
        pendingSpeakChunks = chunks.count
        for (index, chunk) in chunks.enumerated() {
            let utterance = AVSpeechUtterance(string: chunk)
            utterance.voice = bestGermanVoice()
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.94
            utterance.pitchMultiplier = 1.02
            utterance.volume = 1.0
            utterance.preUtteranceDelay = index == 0 ? 0 : 0.04
            utterance.postUtteranceDelay = 0
            synthesizer.speak(utterance)
        }
    }

    private func ensureTTSEngine(format: AVAudioFormat) throws {
        if !ttsEngineReady {
            ttsEngine.attach(ttsPlayer)
            ttsEngine.connect(ttsPlayer, to: ttsEngine.mainMixerNode, format: format)
            // Extra headroom on mixer (linear > 1)
            ttsEngine.mainMixerNode.outputVolume = 1.8
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

    private static func amplifyPCM(_ buffer: AVAudioPCMBuffer, gain: Float) {
        guard let channels = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        for ch in 0..<channelCount {
            let samples = channels[ch]
            for i in 0..<frames {
                // Soft saturation keeps it loud without harsh digital clip
                let boosted = samples[i] * gain
                samples[i] = tanh(boosted * 1.05)
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

        // Primary: transcript stopped changing (user paused) → send immediately
        // Secondary: audio went quiet
        let silenceReady = quietFor >= silenceToEnd
        let shouldSend = force || (spokenLongEnough && (transcriptStable || silenceReady))
        guard shouldSend else { return }

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
        let boosted = min(rms * 10, 1)
        level = level * 0.55 + boosted * 0.45

        if !speechStarted {
            noiseFloor = noiseFloor * 0.95 + level * 0.05
        }
        let speechThreshold = max(0.04, noiseFloor * speechLevelFactor)

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
            let value = min(bandRms * (12 + CGFloat(b) * 0.35), 1)
            next[b] = next[b] * 0.45 + value * 0.55
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

    private func bestGermanVoice() -> AVSpeechSynthesisVoice? {
        let voices = availableGermanVoices()
        if !preferredVoiceIdentifier.isEmpty,
           let preferred = voices.first(where: { $0.identifier == preferredVoiceIdentifier }) {
            return preferred
        }
        let deDE = voices.filter { $0.language.lowercased().hasPrefix("de-de") }
        let pool = deDE.isEmpty ? voices : deDE
        if let premium = pool.first(where: { $0.quality == .premium }) { return premium }
        if let enhanced = pool.first(where: { $0.quality == .enhanced }) { return enhanced }
        let preferredNames = ["anna", "helena", "martin", "petra", "yannick", "viktoria", "markus", "katja"]
        if let named = pool.first(where: { v in preferredNames.contains(where: { v.name.lowercased().contains($0) }) }) {
            return named
        }
        return pool.first ?? AVSpeechSynthesisVoice(language: "de-DE")
    }

    private func voiceScore(_ voice: AVSpeechSynthesisVoice) -> Int {
        var score = 0
        switch voice.quality {
        case .premium: score += 8
        case .enhanced: score += 5
        default: score += 1
        }
        if voice.language.lowercased().hasPrefix("de-de") { score += 3 }
        let name = voice.name.lowercased()
        if ["anna", "helena", "martin", "petra", "yannick", "viktoria", "markus", "katja"].contains(where: { name.contains($0) }) {
            score += 2
        }
        if name.contains("neural") || name.contains("siri") || name.contains("premium") {
            score += 2
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

    static func voiceOnlyPrompt(_ userText: String) -> String {
        userText.trimmingCharacters(in: .whitespacesAndNewlines)
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
