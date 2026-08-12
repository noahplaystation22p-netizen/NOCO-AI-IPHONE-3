import AVFoundation
import Foundation
import WatchKit

/// Watch Voice: UI/dictation text → Flash ask via iPhone → TTS on watch.
/// Uses system dictation (TextField mic) instead of Speech framework for watchOS compatibility.
@MainActor
final class WatchVoiceEngine: ObservableObject {
    @Published private(set) var phase: WatchStatusSnapshot.Phase = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var spokenText = ""
    @Published private(set) var audioLevel: CGFloat = 0.15
    @Published private(set) var isActive = false
    @Published var draft = ""

    private let synthesizer = AVSpeechSynthesizer()
    private var speechDelegate: SpeechDelegate?
    private var priorContext: [String] = []
    private var levelTask: Task<Void, Never>?

    func startSession() async {
        guard !isActive else { return }
        isActive = true
        phase = .listening
        draft = ""
        transcript = ""
        audioLevel = 0.2
        WatchHaptics.voiceStarted()
        WatchHaptics.listening()
        startLevelPulse()
    }

    func stopSession() {
        levelTask?.cancel()
        levelTask = nil
        synthesizer.stopSpeaking(at: .immediate)
        isActive = false
        phase = .idle
        transcript = ""
        draft = ""
        audioLevel = 0.15
    }

    /// Submit dictation / typed text from the Watch UI.
    func submitDraft() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isActive, !text.isEmpty else { return }
        draft = ""
        transcript = text
        priorContext.append(text)
        if priorContext.count > 4 { priorContext.removeFirst() }
        await processAndSpeak(text)
    }

    private func processAndSpeak(_ text: String) async {
        guard isActive else { return }
        phase = .thinking
        levelTask?.cancel()
        audioLevel = 0.35

        let result = await WatchSessionClient.shared.askFlash(text, voice: true)
        guard isActive else { return }

        switch result {
        case .success(let reply):
            spokenText = reply
            phase = .speaking
            WatchHaptics.replyArrived()
            await speak(reply)
            guard isActive else { return }
            phase = .listening
            WatchHaptics.taskDone()
            WatchHaptics.listening()
            startLevelPulse()
        case .failure:
            phase = .error
            WatchHaptics.error()
            try? await Task.sleep(nanoseconds: 900_000_000)
            if isActive {
                phase = .listening
                startLevelPulse()
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

    private func startLevelPulse() {
        levelTask?.cancel()
        levelTask = Task { @MainActor in
            while !Task.isCancelled && isActive && phase == .listening {
                audioLevel = CGFloat.random(in: 0.18...0.45)
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
        }
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
