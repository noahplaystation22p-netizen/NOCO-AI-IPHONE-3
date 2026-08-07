import ActivityKit
import Foundation

@MainActor
enum SpeakLiveActivityManager {
    private static var activity: Activity<SpeakActivityAttributes>?
    private static var lastLevelUpdate: Date = .distantPast

    static var isActive: Bool {
        activity != nil || !Activity<SpeakActivityAttributes>.activities.isEmpty
    }

    static var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Fire-and-forget start (Speak start path).
    static func start(sessionLabel: String = "NOCO Voice AI") {
        Task { _ = await startAndWait(sessionLabel: sessionLabel) }
    }

    /// Guaranteed attempt: end stale activities, then request a new one (retries).
    @discardableResult
    static func startAndWait(sessionLabel: String = "NOCO Voice AI") async -> Bool {
        guard areActivitiesEnabled else { return false }

        // Clear stale activities so a fresh Lock Screen + Island banner appears
        let stale = Activity<SpeakActivityAttributes>.activities
        activity = nil
        for act in stale {
            await act.end(nil, dismissalPolicy: .immediate)
        }

        let attributes = SpeakActivityAttributes(sessionLabel: sessionLabel)
        let state = SpeakActivityAttributes.ContentState(
            phaseRaw: SpeakActivityPhase.listening.rawValue,
            title: SpeakActivityPhase.listening.title,
            detail: "NOCO Voice AI aktiviert — rede natürlich",
            level: 0.35,
            bars: [0.25, 0.45, 0.7, 0.95, 0.7, 0.45, 0.25],
            isOnline: true,
            isMuted: false
        )

        for attempt in 1...4 {
            do {
                let created = try Activity.request(
                    attributes: attributes,
                    content: .init(
                        state: state,
                        staleDate: Date().addingTimeInterval(60 * 60)
                    ),
                    pushType: nil
                )
                activity = created
                return true
            } catch {
                activity = nil
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 250_000_000)
            }
        }

        // Last resort: adopt any activity the system still has
        if let existing = Activity<SpeakActivityAttributes>.activities.first {
            activity = existing
            await existing.update(
                .init(state: state, staleDate: Date().addingTimeInterval(60 * 60))
            )
            return true
        }
        return false
    }

    static func update(
        phase: SpeakActivityPhase,
        detail: String,
        level: Double,
        bars: [Double],
        isOnline: Bool,
        isMuted: Bool = false,
        force: Bool = false,
        titleOverride: String? = nil
    ) {
        if activity == nil {
            activity = Activity<SpeakActivityAttributes>.activities.first
        }
        guard let activity else {
            // Recreate if Speak is somehow running without an activity
            start()
            return
        }

        let now = Date()
            if !force, phase == .listening || phase == .speaking {
            if now.timeIntervalSince(lastLevelUpdate) < 0.14 { return }
        }
        lastLevelUpdate = now

        let title: String
        if isMuted && phase != .speaking {
            title = "Voice AI stumm"
        } else if let titleOverride, !titleOverride.isEmpty {
            title = String(titleOverride.prefix(40))
        } else {
            title = phase.title
        }

        let state = SpeakActivityAttributes.ContentState(
            phaseRaw: phase.rawValue,
            title: title,
            detail: String(detail.prefix(80)),
            level: min(max(level, 0), 1),
            bars: bars.map { min(max($0, 0), 1) },
            isOnline: isOnline,
            isMuted: isMuted
        )

        Task {
            await activity.update(
                .init(state: state, staleDate: Date().addingTimeInterval(60 * 60))
            )
        }
    }

    static func end() {
        let activities = Activity<SpeakActivityAttributes>.activities
        activity = nil
        Task {
            for act in activities {
                await act.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
