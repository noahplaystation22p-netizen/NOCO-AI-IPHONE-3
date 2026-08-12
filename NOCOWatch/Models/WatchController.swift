import Foundation
import SwiftUI

@MainActor
final class WatchController: ObservableObject {
    @Published var section: WatchSection = .ask
    @Published var askText = ""
    @Published var localPhase: WatchStatusSnapshot.Phase = .idle
    @Published var errorLine: String?
    @Published var crownRotation: Double = 0

    let session = WatchSessionClient.shared
    let voice = WatchVoiceEngine()

    private var lastCrownIndex: Int = 0
    private var askInFlight = false

    var snapshot: WatchStatusSnapshot { session.snapshot }

    func onAppear() {
        // Fresh session — don't keep stale thinking/speaking UI.
        localPhase = .idle
        errorLine = nil
        session.activate()
        session.refreshStatus()
        WatchHaptics.appOpened()
    }

    func onDisappear() {
        if voice.isActive {
            voice.stopSession()
        }
        if localPhase == .thinking || localPhase == .speaking {
            localPhase = .idle
        }
        session.cancelActiveAsk()
    }

    func selectSection(_ s: WatchSection) {
        guard section != s else { return }
        section = s
        WatchHaptics.crownSnap()
    }

    func snapCrown(to index: Int) {
        let all = WatchSection.allCases
        guard all.indices.contains(index) else { return }
        guard index != lastCrownIndex else { return }
        lastCrownIndex = index
        selectSection(all[index])
    }

    func submitAsk() async {
        let q = askText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !askInFlight else { return }
        askInFlight = true
        defer { askInFlight = false }

        errorLine = nil
        localPhase = .thinking
        let result = await session.askFlash(q, voice: false)
        switch result {
        case .success:
            askText = ""
            localPhase = .idle
            errorLine = nil
            WatchHaptics.replyArrived()
            section = .last
        case .failure(.cancelled):
            localPhase = .idle
        case .failure(let err):
            localPhase = .idle
            if let msg = err.errorDescription, !msg.isEmpty {
                // Soft reconnect wording instead of hard error flash when restoring.
                if session.watchPhoneLink == .reconnecting {
                    errorLine = WatchUserFacingError.restoring
                } else {
                    errorLine = WatchUserFacingError.sanitize(msg)
                }
            }
            WatchHaptics.error()
        }
    }

    func startVoice() async {
        errorLine = nil
        await voice.startSession()
    }

    func stopVoice() {
        voice.stopSession()
        localPhase = .idle
    }
}

enum WatchSection: String, CaseIterable, Identifiable {
    case ask = "Ask"
    case voice = "Voice"
    case last = "Last"
    case status = "Status"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: return "Ask NOCO"
        case .voice: return "Voice"
        case .last: return "Last Answer"
        case .status: return "Status"
        }
    }

    var symbol: String {
        switch self {
        case .ask: return "text.bubble"
        case .voice: return "waveform"
        case .last: return "clock.arrow.circlepath"
        case .status: return "dot.radiowaves.left.and.right"
        }
    }
}
