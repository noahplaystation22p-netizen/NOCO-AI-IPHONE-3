import ActivityKit
import Foundation

@MainActor
enum SpeakLiveActivityManager {
    private static var activity: Activity<SpeakActivityAttributes>?
    private static var lastLevelUpdate: Date = .distantPast
    private static var lastPhaseRaw: String = ""
    private static var lastDetail: String = ""
    private static var lastTitle: String = ""

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
        if Self.activity == nil {
            Self.activity = Activity<SpeakActivityAttributes>.activities.first
        }
        guard Self.activity != nil || !Activity<SpeakActivityAttributes>.activities.isEmpty else {
            // Recreate if Speak is somehow running without an activity
            start()
            return
        }

        let title: String
        if isMuted && phase != .speaking {
            title = "Voice AI stumm"
        } else if let titleOverride, !titleOverride.isEmpty {
            title = String(titleOverride.prefix(120))
        } else {
            title = phase.title
        }
        // Prefer currently spoken suffix so long replies stay readable on Island.
        let clippedDetail = Self.speakingDetailWindow(detail, maxChars: 360)
        let phaseChanged = phase.rawValue != lastPhaseRaw
        let textChanged = clippedDetail != lastDetail || title != lastTitle
        let now = Date()

        // Phase / copy transitions must never wait behind meter flood.
        // Meter-only updates: lighter throttle so Island stays snappy without queueing.
        if !force, !phaseChanged, !textChanged {
            let minGap: TimeInterval = (phase == .listening || phase == .speaking) ? 0.12 : 0.4
            if now.timeIntervalSince(lastLevelUpdate) < minGap { return }
        }
        lastLevelUpdate = now
        lastPhaseRaw = phase.rawValue
        lastDetail = clippedDetail
        lastTitle = title

        let state = SpeakActivityAttributes.ContentState(
            phaseRaw: phase.rawValue,
            title: title,
            detail: clippedDetail,
            level: min(max(level, 0), 1),
            bars: bars.map { min(max($0, 0), 1) },
            isOnline: isOnline,
            isMuted: isMuted
        )

        Task {
            // Update every system activity — background can leave our local ref stale.
            let activities = Activity<SpeakActivityAttributes>.activities
            if activities.isEmpty {
                SpeakLiveActivityManager.start()
                return
            }
            Self.activity = activities.first
            for act in activities {
                await act.update(
                    .init(state: state, staleDate: Date().addingTimeInterval(60 * 60))
                )
            }
        }
    }

    /// Keep the live spoken tail visible instead of hard-cutting from the start.
    private static func speakingDetailWindow(_ text: String, maxChars: Int) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > maxChars else { return t }
        let tail = String(t.suffix(maxChars))
        if let space = tail.firstIndex(of: " ") {
            let trimmed = String(tail[space...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "…" + tail : "…" + trimmed
        }
        return "…" + tail
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
