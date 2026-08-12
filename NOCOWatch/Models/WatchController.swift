import Foundation
import SwiftUI

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

@MainActor
final class WatchController: ObservableObject {
    @Published var section: WatchSection = .ask
    @Published var askText = ""
    @Published var localPhase: WatchStatusSnapshot.Phase = .idle
    @Published var errorLine: String?
    @Published var crownRotation: Double = 0

    let session = WatchSessionClient.shared
    let voice = WatchVoiceEngine()

    var snapshot: WatchStatusSnapshot { session.snapshot }

    func onAppear() {
        session.activate()
        WatchHaptics.appOpened()
        session.refreshStatus()
    }

    func selectSection(_ s: WatchSection) {
        guard section != s else { return }
        section = s
        WatchHaptics.crownSnap()
    }

    func snapCrown(to index: Int) {
        let all = WatchSection.allCases
        guard all.indices.contains(index) else { return }
        selectSection(all[index])
    }

    func submitAsk() async {
        let q = askText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        errorLine = nil
        localPhase = .thinking
        let result = await session.askFlash(q, voice: false)
        switch result {
        case .success:
            askText = ""
            localPhase = .idle
            WatchHaptics.replyArrived()
        case .failure(let err):
            localPhase = .error
            errorLine = err.localizedDescription
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
