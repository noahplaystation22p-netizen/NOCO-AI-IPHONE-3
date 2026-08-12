import AVFoundation
import Foundation
import Speech

/// Watch Voice: dictation → Flash ask via iPhone → TTS on watch.
@MainActor
final class WatchVoiceEngine: ObservableObject {
    @Published private(set) var phase: WatchStatusSnapshot.Phase = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var spokenText = ""
    @Published private(set) var audioLevel: CGFloat = 0.15
    @Published private(set) var isActive = false

    private let synthesizer = AVSpeechSynthesizer()
    private var speechDelegate: SpeechDelegate?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    private var priorContext: [String] = []

    func startSession() async {
        guard !isActive else { return }
        isActive = true
        phase = .idle
        WatchHaptics.voiceStarted()
        await listenOnce()
    }

    func stopSession() {
        stopRecognition()
        synthesizer.stopSpeaking(at: .immediate)
        isActive = false
        phase = .idle
        transcript = ""
    }

    /// One conversation round; stays active for follow-up if watchOS allows.
    func listenOnce() async {
        guard isActive else { return }
        phase = .listening
        WatchHaptics.listening()
        transcript = ""

        let granted = await requestPermissions()
        guard granted else {
            phase = .error
            WatchHaptics.error()
            return
        }

        guard let text = await transcribe(), !text.isEmpty else {
            if isActive {
                phase = .idle
                try? await Task.sleep(nanoseconds: 400_000_000)
                if isActive { await listenOnce() }
            }
            return
        }

        transcript = text
        priorContext.append(text)
        if priorContext.count > 4 { priorContext.removeFirst() }
        await processAndSpeak(text)
    }

    private func processAndSpeak(_ text: String) async {
        guard isActive else { return }
        phase = .thinking

        let result = await WatchSessionClient.shared.askFlash(text, voice: true)
        guard isActive else { return }

        switch result {
        case .success(let reply):
            spokenText = reply
            phase = .speaking
            WatchHaptics.replyArrived()
            await speak(reply)
            phase = .idle
            WatchHaptics.taskDone()
            try? await Task.sleep(nanoseconds: 500_000_000)
            if isActive { await listenOnce() }
        case .failure:
            phase = .error
            WatchHaptics.error()
            try? await Task.sleep(nanoseconds: 900_000_000)
            if isActive {
                phase = .idle
                await listenOnce()
            }
        }
    }

    private func speak(_ text: String) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
            utterance.rate = 0.52
            utterance.pitchMultiplier = 1.02
            var finished = false
            let delegate = SpeechDelegate {
                guard !finished else { return }
                finished = true
                cont.resume()
            }
            speechDelegate = delegate
            synthesizer.delegate = delegate
            synthesizer.speak(utterance)
        }
    }

    private func requestPermissions() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    private func transcribe() async -> String? {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE")), recognizer.isAvailable else {
            return nil
        }

        return await withCheckedContinuation { cont in
            stopRecognition()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
                let power = buffer.format.channelCount > 0 ? 0.25 : 0.15
                Task { @MainActor in self.audioLevel = CGFloat(power) }
            }

            audioEngine.prepare()
            do {
                try audioEngine.start()
            } catch {
                cont.resume(returning: nil)
                return
            }

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString
                    Task { @MainActor in
                        self.stopRecognition()
                        cont.resume(returning: text)
                    }
                } else if error != nil {
                    Task { @MainActor in
                        self.stopRecognition()
                        cont.resume(returning: nil)
                    }
                }
            }

            // Auto-end after silence window (watch battery friendly)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 5_500_000_000)
                guard let self else { return }
                if self.recognitionTask != nil {
                    self.recognitionTask?.finish()
                }
            }
        }
    }

    private func stopRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine = AVAudioEngine()
        audioLevel = 0.15
    }
}

private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish()
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinish()
    }
}
