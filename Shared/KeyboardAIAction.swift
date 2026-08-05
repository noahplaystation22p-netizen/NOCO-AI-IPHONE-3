import Foundation

/// AI rewrite actions for the keyboard (flash-mode, text-only reply).
enum KeyboardAIAction: String, CaseIterable, Identifiable {
    case improve
    case shorten
    case longer
    case friendlier
    case professional
    case translate
    case summarize
    case noco

    var id: String { rawValue }

    var title: String {
        switch self {
        case .improve: return "Verbessern"
        case .shorten: return "Kürzer"
        case .longer: return "Länger"
        case .friendlier: return "Freundlicher"
        case .professional: return "Professionell"
        case .translate: return "Übersetzen"
        case .summarize: return "Zusammenfassen"
        case .noco: return "NOCO"
        }
    }

    var systemImage: String {
        switch self {
        case .improve: return "wand.and.stars"
        case .shorten: return "arrow.down.right.and.arrow.up.left"
        case .longer: return "arrow.up.left.and.arrow.down.right"
        case .friendlier: return "face.smiling"
        case .professional: return "briefcase"
        case .translate: return "globe"
        case .summarize: return "text.justify.left"
        case .noco: return "sparkles"
        }
    }

    func prompt(for text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let rule = """
        Antworte NUR mit dem fertigen Text — keine Anführungszeichen, kein Intro, keine Erklärung.
        """
        switch self {
        case .improve:
            return "\(rule)\nFormuliere klarer, natürlicher und flüssiger um, behalte die Bedeutung:\n\n\(t)"
        case .shorten:
            return "\(rule)\nKürze deutlich, behalte die Kernaussage:\n\n\(t)"
        case .longer:
            return "\(rule)\nErweitere sinnvoll mit mehr Details und Fluss:\n\n\(t)"
        case .friendlier:
            return "\(rule)\nSchreibe wärmer und freundlicher um:\n\n\(t)"
        case .professional:
            return "\(rule)\nSchreibe formeller und professioneller um:\n\n\(t)"
        case .translate:
            return "\(rule)\nÜbersetze ins Englische. Wenn schon Englisch: ins Deutsche:\n\n\(t)"
        case .summarize:
            return "\(rule)\nFasse kurz und präzise zusammen:\n\n\(t)"
        case .noco:
            return "\(rule)\nDu bist NOCO AI. Verbessere den Text menschlich, smart und hilfreich — behalte die Absicht:\n\n\(t)"
        }
    }
}
