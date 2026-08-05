import ActivityKit
import Foundation

@MainActor
enum SpeakLiveActivityManager {
    private static var activity: Activity<SpeakActivityAttributes>?
    private static var lastLevelUpdate: Date = .distantPast
    private static var startGeneration = 0

    static var isActive: Bool {
        activity != nil || !Activity<SpeakActivityAttributes>.activities.isEmpty
    }

    /// Always create a fresh Live Activity (Lock Screen banner + Dynamic Island).
    static func start(sessionLabel: String = "NOCO Speak") {
        startGeneration += 1
        let gen = startGeneration

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            // Still try — some sideload builds report false incorrectly
            requestNew(sessionLabel: sessionLabel, generation: gen)
            return
        }
        requestNew(sessionLabel: sessionLabel, generation: gen)
    }

    private static func requestNew(sessionLabel: String, generation: Int) {
        // Tear down any stale activities, then create new
        let existing = Activity<SpeakActivityAttributes>.activities
        activity = nil
        Task {
            for act in existing {
                await act.end(nil, dismissalPolicy: .immediate)
            }
            guard generation == startGeneration else { return }
            await MainActor.run {
                createActivity(sessionLabel: sessionLabel)
            }
        }
        // Also try immediately (works when none exist yet)
        if existing.isEmpty {
            createActivity(sessionLabel: sessionLabel)
        }
    }

    private static func createActivity(sessionLabel: String) {
        if activity != nil { return }
        if let live = Activity<SpeakActivityAttributes>.activities.first {
            activity = live
            return
        }

        let attributes = SpeakActivityAttributes(sessionLabel: sessionLabel)
        let state = SpeakActivityAttributes.ContentState(
            phaseRaw: SpeakActivityPhase.listening.rawValue,
            title: "Zuhören…",
            detail: "Sprich — Pause sendet sofort",
            level: 0.25,
            bars: [0.3, 0.5, 0.7, 0.9, 0.7, 0.5, 0.3],
            isOnline: true,
            isMuted: false
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(
                    state: state,
                    staleDate: Date().addingTimeInterval(60 * 60)
                ),
                pushType: nil
            )
        } catch {
            activity = nil
            // One retry shortly after
            Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                await MainActor.run {
                    guard activity == nil,
                          Activity<SpeakActivityAttributes>.activities.isEmpty else { return }
                    do {
                        activity = try Activity.request(
                            attributes: attributes,
                            content: .init(state: state, staleDate: Date().addingTimeInterval(60 * 60)),
                            pushType: nil
                        )
                    } catch {
                        activity = nil
                    }
                }
            }
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
        // If nothing is running, recreate so banner appears
        if activity == nil {
            start()
            activity = Activity<SpeakActivityAttributes>.activities.first
        }
        guard let activity else { return }

        let now = Date()
        if !force, phase == .listening || phase == .speaking {
            if now.timeIntervalSince(lastLevelUpdate) < 0.25 { return }
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
                .init(state: state, staleDate: Date().addingTimeInterval(60 * 60))
            )
        }
    }

    static func end() {
        startGeneration += 1
        let activities = Activity<SpeakActivityAttributes>.activities
        activity = nil
        Task {
            for act in activities {
                await act.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
