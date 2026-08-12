import AVFoundation
import Foundation
import WatchKit

/// Watch Voice: UI/dictation text → Flash ask via iPhone → TTS on watch.
@MainActor
final class WatchVoiceEngine: ObservableObject {
    @Published private(set) var phase: WatchStatusSnapshot.Phase = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var spokenText = ""
    @Published private(set) var audioLevel: CGFloat = 0.15
    @Published private(set) var isActive = false
    @Published private(set) var statusHint: String?
    @Published var draft = ""

    private let synthesizer = AVSpeechSynthesizer()
    private var speechDelegate: SpeechDelegate?
    private var priorContext: [String] = []
    private var levelTask: Task<Void, Never>?
    private var submitInFlight = false
    private var speakContinuation: CheckedContinuation<Void, Never>?

    func startSession() async {
        guard !isActive else { return }
        isActive = true
        phase = .listening
        draft = ""
        transcript = ""
        spokenText = ""
        statusHint = nil
        audioLevel = 0.2
        WatchHaptics.voiceStarted()
        startLevelPulse()
    }

    func stopSession() {
        levelTask?.cancel()
        levelTask = nil
        submitInFlight = false
        synthesizer.stopSpeaking(at: .immediate)
        if let c = speakContinuation {
            speakContinuation = nil
            c.resume()
        }
        speechDelegate = nil
        isActive = false
        phase = .idle
        transcript = ""
        draft = ""
        statusHint = nil
        audioLevel = 0.15
        WatchHaptics.selection()
    }

    /// Submit dictation / typed text from the Watch UI (Flash only).
    func submitDraft() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isActive, !text.isEmpty, !submitInFlight else { return }
        submitInFlight = true
        defer { submitInFlight = false }

        draft = ""
        transcript = text
        statusHint = nil
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
            let clean = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else {
                await softFail(WatchUserFacingError.empty)
                return
            }
            spokenText = clean
            phase = .speaking
            statusHint = nil
            WatchHaptics.replyArrived()
            await speak(clean)
            guard isActive else { return }
            phase = .listening
            statusHint = nil
            startLevelPulse()
        case .failure(.cancelled):
            guard isActive else { return }
            phase = .listening
            startLevelPulse()
        case .failure(let err):
            await softFail(err.errorDescription ?? WatchUserFacingError.unreachable)
        }
    }

    private func softFail(_ message: String) async {
        statusHint = WatchUserFacingError.sanitize(message)
        // Don't freeze in error animation — brief note, then ready again.
        phase = .listening
        WatchHaptics.error()
        try? await Task.sleep(nanoseconds: 700_000_000)
        guard isActive else { return }
        if WatchSessionClient.shared.watchPhoneLink == .reconnecting {
            statusHint = WatchUserFacingError.restoring
        }
        startLevelPulse()
    }

    private func speak(_ text: String) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            speakContinuation = cont
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
            utterance.rate = 0.52
            utterance.pitchMultiplier = 1.02
            var finished = false
            let delegate = SpeechDelegate { [weak self] in
                guard !finished else { return }
                finished = true
                Task { @MainActor in
                    self?.speakContinuation = nil
                    cont.resume()
                }
            }
            speechDelegate = delegate
            synthesizer.delegate = delegate
            synthesizer.speak(utterance)
        }
    }

    private func startLevelPulse() {
        levelTask?.cancel()
        // Lite pulse — avoid busy loops on weak hardware.
        let interval: UInt64 = WatchRenderTier.current == .lite ? 320_000_000 : 200_000_000
        levelTask = Task { @MainActor in
            while !Task.isCancelled && isActive && phase == .listening {
                audioLevel = CGFloat.random(in: 0.18...0.42)
                try? await Task.sleep(nanoseconds: interval)
            }
            if phase != .listening {
                audioLevel = 0.15
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
