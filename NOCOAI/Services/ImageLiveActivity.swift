import ActivityKit
import Foundation

/// Who currently owns the Image Live Activity — prevents Speak/Agent from killing unrelated work.
enum ImageLiveActivityOwner: String {
    case generation
    case eraser
    case speakVision
}

@MainActor
enum ImageLiveActivityManager {
    private static var activity: Activity<ImageActivityAttributes>?
    private static var lastUpdate: Date = .distantPast
    private static var owner: ImageLiveActivityOwner?

    static var isActive: Bool {
        activity != nil || !Activity<ImageActivityAttributes>.activities.isEmpty
    }

    static var currentOwner: ImageLiveActivityOwner? { owner }

    static var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    static func start(prompt: String, owner newOwner: ImageLiveActivityOwner = .generation) {
        guard areActivitiesEnabled else { return }
        end(immediate: true)

        owner = newOwner
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
            activity = Activity<ImageActivityAttributes>.activities.first
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
        if activity == nil {
            activity = Activity<ImageActivityAttributes>.activities.first
        }
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
        adoptIfNeeded()
        guard let activity else {
            owner = nil
            return
        }
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
        owner = nil
    }

    static func fail(_ message: String) {
        adoptIfNeeded()
        guard let activity else {
            owner = nil
            return
        }
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
        owner = nil
    }

    /// Ends image activities. Pass `onlyIfOwner` to avoid wiping another feature's Island.
    static func end(immediate: Bool = false, onlyIfOwner: ImageLiveActivityOwner? = nil) {
        if let onlyIfOwner, owner != onlyIfOwner {
            return
        }
        let activities = Activity<ImageActivityAttributes>.activities
        activity = nil
        owner = nil
        Task {
            for act in activities {
                await act.end(nil, dismissalPolicy: immediate ? .immediate : .default)
            }
        }
    }

    private static func adoptIfNeeded() {
        if activity == nil {
            activity = Activity<ImageActivityAttributes>.activities.first
        }
    }
}
