import AVFoundation
import Foundation
import Speech

/// Dictation polish intensity for NOCO AI Voice Typing on the keyboard.
enum KeyboardDictationStyle: String, CaseIterable, Identifiable {
    case quick
    case intelligent
    case professional

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quick: return "Schnell"
        case .intelligent: return "Intelligent"
        case .professional: return "Professionell"
        }
    }

    var subtitle: String {
        switch self {
        case .quick: return "Rechtschreibung + Satzzeichen"
        case .intelligent: return "Natürliche Formulierung"
        case .professional: return "Geschäftlicher Stil"
        }
    }

    /// Maps to an existing keyboard rewrite action.
    var polishAction: KeyboardAIAction {
        switch self {
        case .quick: return .punctuate
        case .intelligent: return .improve
        case .professional: return .professional
        }
    }

    private static let suiteKey = "nocoai.kb.dictationStyle"

    static var current: KeyboardDictationStyle {
        get {
            let raw = UserDefaults(suiteName: CompanionCredentials.appGroupId)?
                .string(forKey: suiteKey)
                ?? UserDefaults.standard.string(forKey: suiteKey)
            return KeyboardDictationStyle(rawValue: raw ?? "") ?? .intelligent
        }
        set {
            UserDefaults(suiteName: CompanionCredentials.appGroupId)?
                .set(newValue.rawValue, forKey: suiteKey)
            UserDefaults.standard.set(newValue.rawValue, forKey: suiteKey)
        }
    }

    func next() -> KeyboardDictationStyle {
        let all = Self.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }
}

/// Lightweight on-keyboard speech recognition (Full Access required).
@MainActor
final class KeyboardVoiceTyping: ObservableObject {
    @Published var isRecording = false
    @Published var liveTranscript = ""
    @Published var level: CGFloat = 0
    @Published var lastError: String?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?
    private var speechStarted = false
    private var lastVoiceAt: Date?
    private var onAutoEnd: (() -> Void)?
    private let keyboardAudioDisabled = true

    var hasPermission: Bool {
        guard !keyboardAudioDisabled else { return false }
        SFSpeechRecognizer.authorizationStatus() == .authorized
            && AVAudioSession.sharedInstance().recordPermission == .granted
    }

    func requestPermissions() async -> Bool {
        guard !keyboardAudioDisabled else {
            lastError = "Tastatur-Diktat vorübergehend deaktiviert"
            return false
        }
        let speechOK: Bool = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speechOK else {
            lastError = "Spracherkennung erlauben"
            return false
        }
        let micOK: Bool = await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { ok in
                cont.resume(returning: ok)
            }
        }
        if !micOK {
            lastError = "Mikrofon erlauben"
        }
        return micOK
    }

    func start(autoEnd: @escaping () -> Void) throws {
        stop(cancel: true)
        onAutoEnd = autoEnd
        lastError = nil
        liveTranscript = ""
        speechStarted = false
        lastVoiceAt = nil

        guard !keyboardAudioDisabled else {
            lastError = "Tastatur-Diktat vorübergehend deaktiviert"
            throw DictationError.unavailable
        }

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            lastError = "Spracherkennung nicht verfügbar"
            throw DictationError.unavailable
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { throw DictationError.unavailable }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation
        recognitionRequest.addsPunctuation = true
        if #available(iOS 17.0, *) {
            recognitionRequest.requiresOnDeviceRecognition = false
        }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            lastError = "Mikrofon nicht bereit"
            throw DictationError.unavailable
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            Task { @MainActor in
                self?.processLevel(buffer)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
        startSilenceWatcher()

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    let text = result.bestTranscription.formattedString
                    if text != self.liveTranscript {
                        self.liveTranscript = text
                        if !text.isEmpty {
                            self.speechStarted = true
                            self.lastVoiceAt = Date()
                        }
                    }
                }
                if let error {
                    let ns = error as NSError
                    if ns.domain == "kAFAssistantErrorDomain" || ns.code == 216 || ns.code == 203 {
                        return
                    }
                    if self.isRecording, !self.liveTranscript.isEmpty {
                        return
                    }
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    @discardableResult
    func stop(cancel: Bool = false) -> String {
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
        isRecording = false
        level = 0
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }

    private func processLevel(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        for i in 0..<n { sum += abs(channel[i]) }
        let avg = sum / Float(n)
        level = min(1, CGFloat(avg) * 12)
        if avg > 0.02 {
            lastVoiceAt = Date()
            speechStarted = true
        }
    }

    private func startSilenceWatcher() {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard let self, self.isRecording else { return }
                guard self.speechStarted else { continue }
                let quietFor = Date().timeIntervalSince(self.lastVoiceAt ?? .distantPast)
                if quietFor > 1.35, !self.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let end = self.onAutoEnd
                    self.onAutoEnd = nil
                    end?()
                    return
                }
            }
        }
    }

    enum DictationError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Diktat nicht verfügbar" }
    }
}
