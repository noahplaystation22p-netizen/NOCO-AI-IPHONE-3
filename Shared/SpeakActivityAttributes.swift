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
        var isMuted: Bool
    }

    var sessionLabel: String
}

enum SpeakActivityPhase: String {
    case idle
    case listening
    case processing
    case thinking
    case webSearch
    case creatingImage
    case agentWorking
    case vision
    case awaitingConfirm
    case speaking
    case error

    var title: String {
        switch self {
        case .idle: return "Speak bereit"
        case .listening: return "NOCO hört zu"
        case .processing, .thinking: return "NOCO denkt…"
        case .webSearch: return "NOCO sucht im Internet…"
        case .creatingImage: return "NOCO erstellt dein Bild…"
        case .agentWorking: return "NOCO arbeitet…"
        case .vision: return "NOCO sieht…"
        case .awaitingConfirm: return "Bestätigung nötig"
        case .speaking: return "NOCO antwortet"
        case .error: return "Fehler"
        }
    }

    var symbolName: String {
        switch self {
        case .idle: return "mic.fill"
        case .listening: return "ear.fill"
        case .processing, .thinking: return "sparkles"
        case .webSearch: return "globe"
        case .creatingImage: return "paintbrush.pointed.fill"
        case .agentWorking: return "cpu.fill"
        case .vision: return "eye.fill"
        case .awaitingConfirm: return "questionmark.circle.fill"
        case .speaking: return "speaker.wave.3.fill"
        case .error: return "exclamationmark.circle"
        }
    }

    /// Accent for Island / Lock Screen chrome.
    var accentHexHint: String {
        switch self {
        case .listening: return "cyan"
        case .webSearch: return "blue"
        case .creatingImage: return "pink"
        case .agentWorking: return "mint"
        case .vision: return "teal"
        case .speaking: return "purple"
        case .error: return "orange"
        default: return "rainbow"
        }
    }
}
