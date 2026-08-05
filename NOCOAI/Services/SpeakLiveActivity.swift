import ActivityKit
import Foundation

@MainActor
enum SpeakLiveActivityManager {
    private static var activity: Activity<SpeakActivityAttributes>?
    private static var lastLevelUpdate: Date = .distantPast

    static var isActive: Bool {
        if activity != nil { return true }
        return !Activity<SpeakActivityAttributes>.activities.isEmpty
    }

    static func start(sessionLabel: String = "NOCO Speak") {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Reuse existing island activity if still alive
        if let existing = Activity<SpeakActivityAttributes>.activities.first {
            activity = existing
            return
        }
        end()

        let attributes = SpeakActivityAttributes(sessionLabel: sessionLabel)
        let state = SpeakActivityAttributes.ContentState(
            phaseRaw: SpeakActivityPhase.listening.rawValue,
            title: SpeakActivityPhase.listening.title,
            detail: "Sprich — Pause beendet automatisch",
            level: 0,
            bars: Array(repeating: 0.15, count: 7),
            isOnline: true
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            activity = nil
        }
    }

    static func update(
        phase: SpeakActivityPhase,
        detail: String,
        level: Double,
        bars: [Double],
        isOnline: Bool,
        force: Bool = false
    ) {
        if activity == nil {
            activity = Activity<SpeakActivityAttributes>.activities.first
        }
        guard let activity else { return }

        let now = Date()
        if !force, phase == .listening || phase == .speaking {
            if now.timeIntervalSince(lastLevelUpdate) < 0.2 { return }
        }
        lastLevelUpdate = now

        let state = SpeakActivityAttributes.ContentState(
            phaseRaw: phase.rawValue,
            title: phase.title,
            detail: String(detail.prefix(80)),
            level: min(max(level, 0), 1),
            bars: bars.map { min(max($0, 0), 1) },
            isOnline: isOnline
        )

        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    static func end() {
        guard let activity else { return }
        let final = SpeakActivityAttributes.ContentState(
            phaseRaw: SpeakActivityPhase.idle.rawValue,
            title: "Speak beendet",
            detail: "",
            level: 0,
            bars: Array(repeating: 0.1, count: 7),
            isOnline: true
        )
        Task {
            await activity.end(.init(state: final, staleDate: nil), dismissalPolicy: .immediate)
        }
        self.activity = nil
    }
}
