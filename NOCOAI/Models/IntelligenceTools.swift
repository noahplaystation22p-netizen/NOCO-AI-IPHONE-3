import Foundation

/// Apple-style Writing Tools — prompt wrappers sent to the PC chat.
enum WritingTool: String, CaseIterable, Identifiable {
    case rewrite
    case improve
    case shorten
    case expand
    case tone
    case proofread

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rewrite: return "Umschreiben"
        case .improve: return "Verbessern"
        case .shorten: return "Kürzen"
        case .expand: return "Verlängern"
        case .tone: return "Ton ändern"
        case .proofread: return "Grammatik"
        }
    }

    var subtitle: String {
        switch self {
        case .rewrite: return "Klarer und natürlicher"
        case .improve: return "Stil und Lesbarkeit"
        case .shorten: return "Sinn behalten, kürzen"
        case .expand: return "Mehr Detail, gleicher Sinn"
        case .tone: return "Freundlich oder formell"
        case .proofread: return "Rechtschreibung & Grammatik"
        }
    }

    var systemImage: String {
        switch self {
        case .rewrite: return "arrow.triangle.2.circlepath"
        case .improve: return "wand.and.stars"
        case .shorten: return "arrow.down.right.and.arrow.up.left"
        case .expand: return "arrow.up.left.and.arrow.down.right"
        case .tone: return "theatermasks"
        case .proofread: return "checkmark.seal"
        }
    }

    func prompt(for text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .rewrite:
            return """
            Schreibe den Text klarer und natürlicher um. Bedeutung und Absicht bleiben identisch. \
            Nur den fertigen Text zurückgeben.\n\n\(t)
            """
        case .improve:
            return """
            Verbessere Stil, Lesbarkeit und Fluss. Keine neuen Fakten. Nur den fertigen Text.\n\n\(t)
            """
        case .shorten:
            return """
            Kürze den Text auf ca. 45–60%. Entferne Wiederholungen und Füllwörter. \
            Behalte die wichtigsten Informationen. Sinn hat Vorrang vor maximaler Kürze. \
            Nur den fertigen Text.\n\n\(t)
            """
        case .expand:
            return """
            Verlängere den Text sinnvoll (ca. +40–70%). Mehr Klarheit und ein bis zwei Details, \
            die schon angelegt sind — nichts erfinden. Nur den fertigen Text.\n\n\(t)
            """
        case .tone:
            return """
            Liefere ZWEI Varianten des Textes (gleicher Sinn):
            1) Freundlich und warm
            2) Formell und professionell
            Kurze Überschriften, sonst nur die Texte.\n\n\(t)
            """
        case .proofread:
            return """
            Korrigiere Rechtschreibung, Grammatik und Zeichensetzung. Inhalt unverändert. \
            Nur den korrigierten Text zurückgeben.\n\n\(t)
            """
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
        prompt(for: reply, shortenLevel: 1)
    }

    func prompt(for reply: String, shortenLevel: Int) -> String {
        switch self {
        case .shorter:
            let level = min(max(shortenLevel, 1), 4)
            let guidance: String
            switch level {
            case 1:
                guidance = "Stufe 1 — leicht gekürzt (~75%): nur Füllwörter und Wiederholungen weg. Sinn und Details bleiben."
            case 2:
                guidance = "Stufe 2 — deutlich kürzer (~50%): Nebensätze reduzieren, Kernaussagen behalten."
            case 3:
                guidance = "Stufe 3 — Kurzfassung (~30%): nur die wichtigsten Punkte, weiterhin voll verständlich."
            default:
                guidance = "Stufe 4 — ein klarer Satz: die zentrale Aussage, nichts Wesentliches verlieren."
            }
            return """
            Kürze deine letzte Antwort intelligent (nicht nur Wörter löschen).
            \(guidance)
            Verstehe den Inhalt, behalte Sinn und Fakten. Kein Meta-Kommentar — nur die gekürzte Antwort.
            """
        case .longer:
            return "Erweitere deine letzte Antwort mit mehr Details und Beispielen — gleiche Kernaussage."
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
