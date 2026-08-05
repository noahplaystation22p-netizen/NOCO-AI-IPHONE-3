import ActivityKit
import Foundation

/// Shared between app + Speak widget extension.
struct SpeakActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var phaseRaw: String
        var title: String
        var detail: String
        var level: Double
        var bars: [Double]
        var isOnline: Bool
    }

    var sessionLabel: String
}

enum SpeakActivityPhase: String {
    case idle
    case listening
    case processing
    case speaking
    case error

    var title: String {
        switch self {
        case .idle: return "Speak bereit"
        case .listening: return "Zuhören…"
        case .processing: return "PC denkt…"
        case .speaking: return "Spoken Reply"
        case .error: return "Fehler"
        }
    }
}
