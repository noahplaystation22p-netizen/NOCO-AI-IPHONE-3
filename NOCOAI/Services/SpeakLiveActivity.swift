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
        if let existing = Activity<SpeakActivityAttributes>.activities.first {
            activity = existing
            return
        }
        end()

        let attributes = SpeakActivityAttributes(sessionLabel: sessionLabel)
        let state = SpeakActivityAttributes.ContentState(
            phaseRaw: SpeakActivityPhase.listening.rawValue,
            title: SpeakActivityPhase.listening.title,
            detail: "Sprich — Pause sendet automatisch",
            level: 0.2,
            bars: Array(repeating: 0.2, count: 7),
            isOnline: true,
            isMuted: false
        )

        do {
            // Shows Lock Screen banner + Dynamic Island immediately
            activity = try Activity.request(
                attributes: attributes,
                content: .init(
                    state: state,
                    staleDate: Date().addingTimeInterval(60 * 30)
                ),
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
        isMuted: Bool = false,
        force: Bool = false
    ) {
        if activity == nil {
            activity = Activity<SpeakActivityAttributes>.activities.first
        }
        guard let activity else { return }

        let now = Date()
        if !force, phase == .listening || phase == .speaking {
            if now.timeIntervalSince(lastLevelUpdate) < 0.18 { return }
        }
        lastLevelUpdate = now

        let title: String
        if isMuted && phase != .speaking {
            title = "Stumm"
        } else {
            title = phase.title
        }

        let state = SpeakActivityAttributes.ContentState(
            phaseRaw: phase.rawValue,
            title: title,
            detail: String(detail.prefix(100)),
            level: min(max(level, 0), 1),
            bars: bars.map { min(max($0, 0), 1) },
            isOnline: isOnline,
            isMuted: isMuted
        )

        Task {
            await activity.update(
                .init(state: state, staleDate: Date().addingTimeInterval(60 * 30))
            )
        }
    }

    static func end() {
        let activities = Activity<SpeakActivityAttributes>.activities
        let final = SpeakActivityAttributes.ContentState(
            phaseRaw: SpeakActivityPhase.idle.rawValue,
            title: "Speak beendet",
            detail: "",
            level: 0,
            bars: Array(repeating: 0.1, count: 7),
            isOnline: true,
            isMuted: false
        )
        Task {
            for act in activities {
                await act.end(.init(state: final, staleDate: nil), dismissalPolicy: .immediate)
            }
        }
        activity = nil
    }
}
