import ActivityKit
import Foundation

@MainActor
enum AgentLiveActivityManager {
    private static var activity: Activity<AgentActivityAttributes>?
    private static var lastUpdate: Date = .distantPast

    static var isActive: Bool {
        activity != nil || !Activity<AgentActivityAttributes>.activities.isEmpty
    }

    static var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    static func start(goal: String) {
        guard areActivitiesEnabled else { return }
        end(immediate: true)

        let attributes = AgentActivityAttributes(goal: String(goal.prefix(80)))
        let state = AgentActivityAttributes.ContentState(
            progress: 0.05,
            percentLabel: "5%",
            status: AgentActivityPhase.planning.title,
            insight: "Plant Aufgabe…",
            phaseRaw: AgentActivityPhase.planning.rawValue,
            isDone: false
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: Date().addingTimeInterval(60 * 60)),
                pushType: nil
            )
        } catch {
            activity = Activity<AgentActivityAttributes>.activities.first
        }
    }

    static func update(
        progress: Double,
        status: String,
        insight: String,
        phase: AgentActivityPhase,
        force: Bool = false
    ) {
        if activity == nil {
            activity = Activity<AgentActivityAttributes>.activities.first
        }
        guard let activity else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastUpdate) < 0.8 { return }
        lastUpdate = now

        let pct = min(max(progress, 0), 1)
        let state = AgentActivityAttributes.ContentState(
            progress: pct,
            percentLabel: "\(Int(pct * 100))%",
            status: String(status.prefix(60)),
            insight: String(insight.prefix(80)),
            phaseRaw: phase.rawValue,
            isDone: phase == .done
        )

        Task {
            await activity.update(
                .init(state: state, staleDate: Date().addingTimeInterval(60 * 60))
            )
        }
    }

    static func complete(goal: String) {
        adoptIfNeeded()
        guard let activity else { return }
        let state = AgentActivityAttributes.ContentState(
            progress: 1,
            percentLabel: "100%",
            status: AgentActivityPhase.done.title,
            insight: String(goal.prefix(60)),
            phaseRaw: AgentActivityPhase.done.rawValue,
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
        adoptIfNeeded()
        guard let activity else { return }
        let state = AgentActivityAttributes.ContentState(
            progress: 0,
            percentLabel: "—",
            status: AgentActivityPhase.error.title,
            insight: String(message.prefix(80)),
            phaseRaw: AgentActivityPhase.error.rawValue,
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
        let activities = Activity<AgentActivityAttributes>.activities
        activity = nil
        Task {
            for act in activities {
                await act.end(nil, dismissalPolicy: immediate ? .immediate : .default)
            }
        }
    }

    private static func adoptIfNeeded() {
        if activity == nil {
            activity = Activity<AgentActivityAttributes>.activities.first
        }
    }
}
