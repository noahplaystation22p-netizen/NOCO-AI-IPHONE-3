import ActivityKit
import Foundation

@MainActor
enum ImageLiveActivityManager {
    private static var activity: Activity<ImageActivityAttributes>?
    private static var lastUpdate: Date = .distantPast

    static var isActive: Bool { activity != nil }

    static func start(prompt: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end(immediate: true)

        let attributes = ImageActivityAttributes(prompt: String(prompt.prefix(80)))
        let state = ImageActivityAttributes.ContentState(
            progress: 0.02,
            percentLabel: "2%",
            status: ImageActivityPhase.preparing.title,
            insight: "Motiv nimmt Form an…",
            etaLabel: "~4 Min",
            phaseRaw: ImageActivityPhase.preparing.rawValue,
            isDone: false
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: Date().addingTimeInterval(600)),
                pushType: nil
            )
        } catch {
            activity = nil
        }
    }

    static func update(
        progress: Double,
        status: String,
        insight: String,
        etaSeconds: Int?,
        phase: ImageActivityPhase,
        force: Bool = false
    ) {
        guard let activity else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastUpdate) < 0.8 { return }
        lastUpdate = now

        let pct = min(max(progress, 0), 1)
        let eta: String
        if let etaSeconds, etaSeconds > 0 {
            let m = etaSeconds / 60
            let s = etaSeconds % 60
            eta = m > 0 ? "~\(m) Min \(s)s" : "~\(s)s"
        } else {
            eta = "…"
        }

        let state = ImageActivityAttributes.ContentState(
            progress: pct,
            percentLabel: "\(Int(pct * 100))%",
            status: String(status.prefix(60)),
            insight: String(insight.prefix(80)),
            etaLabel: eta,
            phaseRaw: phase.rawValue,
            isDone: phase == .done
        )

        Task {
            await activity.update(
                .init(state: state, staleDate: Date().addingTimeInterval(600))
            )
        }
    }

    static func complete(prompt: String) {
        guard let activity else { return }
        let state = ImageActivityAttributes.ContentState(
            progress: 1,
            percentLabel: "100%",
            status: "Fertig",
            insight: String(prompt.prefix(60)),
            etaLabel: "Bereit",
            phaseRaw: ImageActivityPhase.done.rawValue,
            isDone: true
        )
        Task {
            await activity.end(
                .init(state: state, staleDate: nil),
                dismissalPolicy: .default
            )
        }
        self.activity = nil
    }

    static func fail(_ message: String) {
        guard let activity else { return }
        let state = ImageActivityAttributes.ContentState(
            progress: 0,
            percentLabel: "—",
            status: "Fehlgeschlagen",
            insight: String(message.prefix(80)),
            etaLabel: "",
            phaseRaw: ImageActivityPhase.error.rawValue,
            isDone: false
        )
        Task {
            await activity.end(
                .init(state: state, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        self.activity = nil
    }

    static func end(immediate: Bool = false) {
        guard let activity else { return }
        let state = ImageActivityAttributes.ContentState(
            progress: 0,
            percentLabel: "",
            status: "",
            insight: "",
            etaLabel: "",
            phaseRaw: ImageActivityPhase.preparing.rawValue,
            isDone: false
        )
        Task {
            await activity.end(
                .init(state: state, staleDate: nil),
                dismissalPolicy: immediate ? .immediate : .default
            )
        }
        self.activity = nil
    }
}
