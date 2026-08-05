import ActivityKit
import Foundation

/// Shared between app + Speak/Image widget extension.
struct ImageActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var progress: Double
        var percentLabel: String
        var status: String
        var insight: String
        var etaLabel: String
        var phaseRaw: String
        var isDone: Bool
    }

    var prompt: String
}

enum ImageActivityPhase: String {
    case preparing
    case rendering
    case finishing
    case done
    case error

    var title: String {
        switch self {
        case .preparing: return "Bild startet…"
        case .rendering: return "Erzeuge Bild…"
        case .finishing: return "Gleich fertig…"
        case .done: return "Bild fertig"
        case .error: return "Fehler"
        }
    }
}
