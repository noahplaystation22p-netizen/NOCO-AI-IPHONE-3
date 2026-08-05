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
        case .improve: return "checkmark.circle"
        case .shorten: return "arrow.down.right.and.arrow.up.left"
        case .longer: return "arrow.up.left.and.arrow.down.right"
        case .friendlier: return "face.smiling"
        case .professional: return "briefcase"
        case .translate: return "globe"
        case .summarize: return "text.justify.left"
        case .noco: return "sparkles"
        }
    }

    var isPrimary: Bool { self == .improve }

    func prompt(for text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let rule = """
        Aufgabe: Textbearbeitung. Antworte AUSSCHLIESSLICH mit dem fertigen Ergebnistext.
        VERBOTEN: Begrüßung, Intro, Erklärung, Anführungszeichen um den Text, Markdown, Aufzählungen, „Gerne“, „Hier ist“, „Hallo“, „Ich bin“.
        """
        switch self {
        case .improve:
            return """
            \(rule)
            Korrigiere nur Rechtschreibung, Grammatik und Zeichensetzung.
            Ändere Wortwahl nur wenn nötig für Klarheit. Länge und Ton bleiben gleich.

            TEXT:
            \(t)
            """
        case .shorten:
            return "\(rule)\nKürze auf das Wesentliche (ca. 50–70%), behalte die Aussage:\n\nTEXT:\n\(t)"
        case .longer:
            return "\(rule)\nErweitere natürlich mit 1–3 sinnvollen Details, ohne Floskeln:\n\nTEXT:\n\(t)"
        case .friendlier:
            return "\(rule)\nSchreibe wärmer und freundlicher, gleiche Länge ungefähr:\n\nTEXT:\n\(t)"
        case .professional:
            return "\(rule)\nSchreibe klar, formell und professionell:\n\nTEXT:\n\(t)"
        case .translate:
            return "\(rule)\nÜbersetze ins Englische. Wenn der Text schon Englisch ist: ins Deutsche. Nur die Übersetzung:\n\nTEXT:\n\(t)"
        case .summarize:
            return "\(rule)\nFasse in 1–3 kurzen Sätzen zusammen:\n\nTEXT:\n\(t)"
        case .noco:
            return "\(rule)\nVerbessere den Text smart und natürlich — behalte Absicht und Länge ungefähr:\n\nTEXT:\n\(t)"
        }
    }

    /// Strip model chatter so replacement stays clean.
    static func sanitize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let bannedPrefixes = [
            "gerne", "hier ist", "hier sind", "sure", "certainly", "of course",
            "hallo", "hi,", "hey,", "ich bin", "als ki", "als sprachmodell",
            "improved:", "corrected:", "übersetzung:", "zusammenfassung:"
        ]
        let lines = s.components(separatedBy: .newlines)
        if let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            if bannedPrefixes.contains(where: { first.hasPrefix($0) }) && lines.count > 1 {
                s = lines.dropFirst().joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if (s.hasPrefix("\"") && s.hasSuffix("\""))
            || (s.hasPrefix("„") && s.hasSuffix("“"))
            || (s.hasPrefix("'") && s.hasSuffix("'")) {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if s.hasPrefix("```") {
            s = s.replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }
}
