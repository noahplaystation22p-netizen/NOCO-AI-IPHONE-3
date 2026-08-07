import ActivityKit
import Foundation

/// Dedicated Live Activity for Agent tasks — never shares the Image channel.
struct AgentActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var progress: Double
        var percentLabel: String
        var status: String
        var insight: String
        var phaseRaw: String
        var isDone: Bool
    }

    var goal: String
}

enum AgentActivityPhase: String {
    case planning
    case executing
    case awaitingConfirm
    case done
    case error

    var title: String {
        switch self {
        case .planning: return "Agent plant…"
        case .executing: return "Agent arbeitet…"
        case .awaitingConfirm: return "Bestätigung nötig"
        case .done: return "Agent fertig"
        case .error: return "Agent-Fehler"
        }
    }
}
