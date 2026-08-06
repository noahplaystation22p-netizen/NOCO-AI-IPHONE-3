import Foundation

/// AI rewrite actions for the keyboard (flash-mode, text-only rewrite — never Q&A).
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

    /// Absolute rule: rewrite the user's text — never answer it as a question.
    private var rewriterRule: String {
        """
        Du bist ein Text-Korrektor / Umformulierer — KEIN Chatbot und KEIN Wissensassistent.
        Der Text unter TEXT ist zu BEARBEITEN, auch wenn er wie eine Frage aussieht.
        VERBOTEN: die Frage beantworten, erklären, definieren, Tipps geben, Wissen hinzufügen,
        Begrüßung, Intro, Markdown, Anführungszeichen um den ganzen Text, „Gerne“, „Hier ist“, „Das bedeutet“.
        Antworte AUSSCHLIESSLICH mit dem fertigen Ergebnistext — nichts sonst.
        """
    }

    func prompt(for text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let example = """
        Beispiel (nur Korrektur, KEINE Antwort):
        TEXT: was ist ein Duft?
        RICHTIG: Was ist ein Duft?
        FALSCH: Ein Duft ist ein Geruch / Aroma …
        """
        switch self {
        case .improve:
            return """
            \(rewriterRule)
            \(example)
            Aufgabe: NUR Rechtschreibung, Grammatik und Zeichensetzung korrigieren.
            Formuliere höchstens minimal klarer. Gleiche Länge (±15%). Keine längere Fassung.
            Wenn der Text eine Frage ist, bleibt es eine Frage — beantworte sie NICHT.
            Keine Definitionen, kein Wissen, keine Erklärungen.

            TEXT:
            \(t)
            """
        case .shorten:
            return """
            \(rewriterRule)
            \(example)
            Aufgabe: Kürze denselben Text (ca. 50–70% der Länge). Behalte die Aussage / Frage.
            Wenn es eine Frage ist: kürze die Frage, beantworte sie nicht.

            TEXT:
            \(t)
            """
        case .longer:
            return """
            \(rewriterRule)
            Aufgabe: Erweitere denselben Text leicht (mehr Fluss, 1–2 Details), ohne die Aussage zu ändern.
            Wenn es eine Frage ist: formuliere die Frage ausführlicher — beantworte sie nicht.

            TEXT:
            \(t)
            """
        case .friendlier:
            return """
            \(rewriterRule)
            Aufgabe: Schreibe denselben Text wärmer/freundlicher, ungefähr gleiche Länge.
            Keine Antwort auf den Inhalt — nur Ton ändern.

            TEXT:
            \(t)
            """
        case .professional:
            return """
            \(rewriterRule)
            Aufgabe: Schreibe denselben Text formeller/professioneller, ungefähr gleiche Länge.
            Keine Antwort auf den Inhalt — nur Stil ändern.

            TEXT:
            \(t)
            """
        case .translate:
            return """
            \(rewriterRule)
            Aufgabe: Übersetze denselben Text. EN↔DE. Nur die Übersetzung, keine Erklärung.
            Wenn es eine Frage ist: übersetze die Frage, beantworte sie nicht.

            TEXT:
            \(t)
            """
        case .summarize:
            return """
            \(rewriterRule)
            Aufgabe: Fasse denselben Text in 1–2 kurzen Sätzen zusammen (Komprimat des Textes, keine neue Antwort).

            TEXT:
            \(t)
            """
        case .noco:
            return """
            \(rewriterRule)
            \(example)
            Aufgabe: Verbessere denselben Text menschlich und klar. Gleiche Absicht, ähnliche Länge.
            Wenn es eine Frage ist: verbessere die Frage — beantworte sie nicht.

            TEXT:
            \(t)
            """
        }
    }

    /// Strip model chatter; clamp runaway “answers” for rewrite actions.
    static func sanitize(_ raw: String, action: KeyboardAIAction, original: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let bannedPrefixes = [
            "gerne", "hier ist", "hier sind", "sure", "certainly", "of course",
            "hallo", "hi,", "hey,", "ich bin", "als ki", "als sprachmodell",
            "improved:", "corrected:", "übersetzung:", "zusammenfassung:",
            "ein duft ist", "a scent is", "das bedeutet", "das heißt",
            "kurz gesagt", "zusammengefasst:", "die antwort", "answer:"
        ]
        let lines = s.components(separatedBy: .newlines)
        if let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            if bannedPrefixes.contains(where: { first.hasPrefix($0) }) {
                if lines.count > 1 {
                    s = lines.dropFirst().joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
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

        let orig = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let origIsQuestion = orig.contains("?") || orig.contains("？")
            || orig.lowercased().hasPrefix("was ") || orig.lowercased().hasPrefix("wie ")
            || orig.lowercased().hasPrefix("wer ") || orig.lowercased().hasPrefix("wo ")
            || orig.lowercased().hasPrefix("warum ") || orig.lowercased().hasPrefix("wann ")
            || orig.lowercased().hasPrefix("what ") || orig.lowercased().hasPrefix("how ")
            || orig.lowercased().hasPrefix("why ") || orig.lowercased().hasPrefix("when ")
            || orig.lowercased().hasPrefix("who ") || orig.lowercased().hasPrefix("where ")

        // Improve / tone: reject inflated “answers” — stay close to original length
        if action == .improve || action == .friendlier || action == .professional || action == .noco {
            let maxLen = max(orig.count + 12, Int(Double(orig.count) * 1.22) + 4)
            if s.count > maxLen {
                // Likely answered the question — keep first sentence if short enough, else fall back
                let endMarks: [Character] = [".", "?", "!", "。", "？", "！"]
                if let idx = s.firstIndex(where: { endMarks.contains($0) }) {
                    let first = String(s[...idx]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if first.count <= maxLen, first.count >= max(3, orig.count / 3) {
                        s = first
                    } else {
                        s = orig
                    }
                } else {
                    s = orig
                }
            }
            // Question in → must stay a question (never a definition)
            if origIsQuestion {
                let outIsQuestion = s.contains("?") || s.contains("？")
                let looksLikeDefinition = s.lowercased().contains(" is ") || s.lowercased().hasPrefix("ein ")
                    || s.lowercased().hasPrefix("eine ") || s.lowercased().hasPrefix("der ")
                    || s.lowercased().hasPrefix("die ") || s.lowercased().hasPrefix("das ")
                    || s.lowercased().hasPrefix("a ") || s.lowercased().hasPrefix("an ")
                    || s.lowercased().hasPrefix("the ")
                if !outIsQuestion || (looksLikeDefinition && s.count > orig.count + 8) {
                    s = polishQuestionFallback(orig)
                }
            }
        }
        if action == .shorten {
            // If model answered instead of shortening, prefer keeping the original question
            let maxLen = max(8, Int(Double(orig.count) * 0.75) + 6)
            if s.count > orig.count + 20 {
                if origIsQuestion {
                    s = polishQuestionFallback(orig)
                } else {
                    s = String(s.prefix(maxLen)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else if s.count > maxLen + 30 {
                s = String(s.prefix(maxLen)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return s
    }

    /// Light local polish when the model answered instead of rewriting a question.
    private static func polishQuestionFallback(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return t }
        // Capitalize first letter
        let first = t.prefix(1).uppercased()
        let rest = String(t.dropFirst())
        t = first + rest
        if !t.hasSuffix("?"), !t.hasSuffix("？") {
            t += "?"
        }
        return t
    }
}
