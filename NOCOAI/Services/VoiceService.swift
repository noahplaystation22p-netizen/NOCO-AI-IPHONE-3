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
    @Published var isAuthorized = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let synthesizer = AVSpeechSynthesizer()
    private var levelTimer: Timer?

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

    func startListening() throws {
        stopSpeaking()
        stopListening(cancel: true)

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            phase = .error("Spracherkennung nicht verfügbar")
            return
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation
        if speechRecognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = false
        }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            self?.updateLevel(from: buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        liveTranscript = ""
        phase = .listening
        HapticService.medium()

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.liveTranscript = result.bestTranscription.formattedString
                }
                if let error {
                    // Normal end-of-utterance often surfaces as an error; keep transcript.
                    let ns = error as NSError
                    if ns.domain == "kAFAssistantErrorDomain" || ns.code == 216 || ns.code == 203 {
                        return
                    }
                    if case .listening = self.phase, self.liveTranscript.isEmpty {
                        self.stopListening(cancel: true)
                        self.phase = .error("Nichts verstanden — nochmal tippen oder sprechen")
                    }
                }
            }
        }
    }

    func stopListening(cancel: Bool = false) {
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
        levelTimer?.invalidate()
        level = 0
        if case .listening = phase {
            phase = liveTranscript.isEmpty ? .idle : .processing
        }
    }

    func finishUtterance() -> String {
        stopListening(cancel: false)
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = text.isEmpty ? .idle : .processing
        return text
    }

    func speak(_ text: String) {
        let cleaned = text
            .replacingOccurrences(of: #"\*\*|__|`|#+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            phase = .idle
            return
        }

        stopSpeaking()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch { /* continue */ }

        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = bestGermanVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        utterance.pitchMultiplier = 1.04
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.05
        phase = .speaking
        HapticService.soft()
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        if case .speaking = phase {
            phase = .idle
        }
    }

    func availableGermanVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("de") }
            .sorted { lhs, rhs in
                voiceScore(lhs) > voiceScore(rhs)
            }
    }

    private func bestGermanVoice() -> AVSpeechSynthesisVoice? {
        let voices = availableGermanVoices()
        if let preferred = voices.first(where: { $0.identifier == preferredVoiceIdentifier }) {
            return preferred
        }
        // Prefer premium / enhanced quality voices
        if let premium = voices.first(where: { voiceScore($0) >= 3 }) { return premium }
        return voices.first ?? AVSpeechSynthesisVoice(language: "de-DE")
    }

    private func voiceScore(_ voice: AVSpeechSynthesisVoice) -> Int {
        var score = 0
        let q = voice.quality
        if q == .premium { score += 4 }
        else if q == .enhanced { score += 3 }
        else { score += 1 }
        let name = voice.name.lowercased()
        if name.contains("anna") || name.contains("helena") || name.contains("markus") || name.contains("petra") {
            score += 1
        }
        return score
    }

    private func updateLevel(from buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        var sum: Float = 0
        for i in 0..<frames {
            let v = channel[i]
            sum += v * v
        }
        let rms = sqrt(sum / Float(frames))
        let normalized = min(CGFloat(rms * 8), 1)
        Task { @MainActor in
            self.level = self.level * 0.7 + normalized * 0.3
        }
    }
}

extension VoiceService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.phase = .idle
            HapticService.success()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.phase = .idle
        }
    }
}
