import Foundation

/// Apple-style Writing Tools — prompt wrappers sent to the PC chat.
enum WritingTool: String, CaseIterable, Identifiable {
    case rewrite
    case proofread
    case summarize
    case simplify
    case bullets
    case translate
    case keyPoints
    case friendly
    case professional

    var id: String { rawValue }

    /// Apple-like German product name
    var title: String {
        switch self {
        case .rewrite: return "Umformulieren"
        case .proofread: return "Korrekturlesen"
        case .summarize: return "Zusammenfassen"
        case .simplify: return "Einfacher"
        case .bullets: return "Stichpunkte"
        case .translate: return "Übersetzen"
        case .keyPoints: return "Kernaussagen"
        case .friendly: return "Freundlicher"
        case .professional: return "Formeller"
        }
    }

    var systemImage: String {
        switch self {
        case .rewrite: return "arrow.triangle.2.circlepath"
        case .proofread: return "checkmark.seal"
        case .summarize: return "text.justify.left"
        case .simplify: return "textformat.size"
        case .bullets: return "list.bullet"
        case .translate: return "globe"
        case .keyPoints: return "lightbulb"
        case .friendly: return "face.smiling"
        case .professional: return "briefcase"
        }
    }

    func prompt(for text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .rewrite:
            return "Formuliere den folgenden Text klarer und natürlicher um, behalte die Bedeutung:\n\n\(t)"
        case .proofread:
            return "Korrigiere Rechtschreibung, Grammatik und Zeichensetzung. Gib nur den korrigierten Text zurück:\n\n\(t)"
        case .summarize:
            return "Fasse den folgenden Text kurz und präzise zusammen:\n\n\(t)"
        case .simplify:
            return "Erkläre den folgenden Text einfacher und verständlicher:\n\n\(t)"
        case .bullets:
            return "Wandle den folgenden Text in klare Stichpunkte um:\n\n\(t)"
        case .translate:
            return "Übersetze den folgenden Text ins Englische. Wenn er schon Englisch ist, übersetze ins Deutsche:\n\n\(t)"
        case .keyPoints:
            return "Extrahiere die wichtigsten Kernaussagen als kurze Liste:\n\n\(t)"
        case .friendly:
            return "Schreibe den folgenden Text freundlicher und wärmer um:\n\n\(t)"
        case .professional:
            return "Schreibe den folgenden Text formeller und professioneller um:\n\n\(t)"
        }
    }
}

/// Follow-up actions on an assistant reply (Windows message actions, Apple naming).
enum ReplyAction: String, CaseIterable, Identifiable {
    case shorter
    case longer
    case asList
    case continueThinking
    case asImagePrompt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shorter: return "Kürzer"
        case .longer: return "Ausführlicher"
        case .asList: return "Als Liste"
        case .continueThinking: return "Weiterdenken"
        case .asImagePrompt: return "Als Bildidee"
        }
    }

    var systemImage: String {
        switch self {
        case .shorter: return "arrow.down.right.and.arrow.up.left"
        case .longer: return "arrow.up.left.and.arrow.down.right"
        case .asList: return "list.bullet"
        case .continueThinking: return "brain.head.profile"
        case .asImagePrompt: return "paintbrush.pointed"
        }
    }

    func prompt(for reply: String) -> String {
        switch self {
        case .shorter:
            return "Mache deine letzte Antwort deutlich kürzer und knapper."
        case .longer:
            return "Erweitere deine letzte Antwort mit mehr Details und Beispielen."
        case .asList:
            return "Strukturiere deine letzte Antwort als klare, gut lesbare Liste."
        case .continueThinking:
            return "Denk weiter zu dem Thema und ergänze wichtige Punkte, die noch fehlen."
        case .asImagePrompt:
            return "Formuliere aus deiner letzten Antwort einen starken Prompt zum Bilderzeugen (1–2 Sätze, deutsch)."
        }
    }
}

/// Empty-state suggestion chips (Windows smart suggestions).
enum IntelligenceIdea: String, CaseIterable, Identifiable {
    case whatCanYou
    case createImage
    case summarize
    case goDeeper
    case codeHelp
    case translate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whatCanYou: return "Was kannst du?"
        case .createImage: return "Bildidee"
        case .summarize: return "Zusammenfassen"
        case .goDeeper: return "Tiefer gehen"
        case .codeHelp: return "Code Assist"
        case .translate: return "Übersetzen"
        }
    }

    var prompt: String {
        switch self {
        case .whatCanYou:
            return "Was kannst du als System-KI? Kurz Speak, Vision Live, Agent, Live Screen, Chat und Bilder erklären."
        case .createImage:
            return "Hilf mir, einen starken Prompt für ein Bild zu schreiben. Frage kurz nach Stil und Motiv."
        case .summarize:
            return "Erkläre mir kurz, wie ich Texte mit dir zusammenfassen und weiterverarbeiten kann."
        case .goDeeper:
            return "Wähle ein spannendes Alltagsthema und erkläre es mir in der Tiefe (Nachdenken)."
        case .codeHelp:
            return "Ich brauche Hilfe beim Programmieren — frage kurz, welche Sprache und was ich bauen will."
        case .translate:
            return "Übersetze auf Anfrage Texte flüssig zwischen Deutsch und Englisch. Sag kurz Bescheid, dass du bereit bist."
        }
    }
}
