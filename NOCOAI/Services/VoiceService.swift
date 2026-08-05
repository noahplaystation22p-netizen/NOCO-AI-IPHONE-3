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

    /// Quiet after speech before auto-send.
    private let silenceToEnd: TimeInterval = 0.85
    private let minSpeechSeconds: TimeInterval = 0.32
    private let speechLevelFactor: CGFloat = 2.2

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
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetooth, .duckOthers]
        )
        try session.overrideOutputAudioPort(.speaker)
        try session.setActive(true, options: [])
    }

    /// Loud TTS route — avoid voiceChat ducking; force speaker.
    func activateLoudPlaybackSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.defaultToSpeaker, .allowBluetoothA2DP]
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
                        return
                    }
                    if case .listening = self.phase, self.liveTranscript.isEmpty {
                        self.stopListening(cancel: true)
                        self.phase = .error("Nichts verstanden — nochmal sprechen")
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
        phase = .speaking
        HapticService.soft()

        Task { await animateSpeakingBands() }

        for (index, chunk) in chunks.enumerated() {
            let utterance = AVSpeechUtterance(string: chunk)
            utterance.voice = bestGermanVoice()
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
            utterance.pitchMultiplier = 1.05
            // Max utterance volume; session route boosts perceived loudness
            utterance.volume = 1.0
            utterance.preUtteranceDelay = index == 0 ? 0.05 : 0.08
            utterance.postUtteranceDelay = 0.05
            synthesizer.speak(utterance)
        }
    }

    func stopSpeaking(notifyFinished: Bool = true) {
        let wasSpeaking = synthesizer.isSpeaking || phase == .speaking
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        pendingSpeakChunks = 0
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
        guard !text.isEmpty, speechStarted else { return }

        let now = Date()
        let lastActivity = max(lastVoiceAt ?? .distantPast, lastTranscriptChangeAt ?? .distantPast)
        let quietFor = now.timeIntervalSince(lastActivity)
        let spokenLongEnough = speechStartAt.map { now.timeIntervalSince($0) >= minSpeechSeconds } ?? false

        let longEnough = text.count >= 2
        let silenceReady = quietFor >= silenceToEnd && spokenLongEnough
        guard force || (longEnough && silenceReady) else { return }

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
            if !synthesizer.isSpeaking {
                self.phase = .idle
                HapticService.success()
                self.notifySpeakFinishedOnce()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.phase = .idle
        }
    }
}
