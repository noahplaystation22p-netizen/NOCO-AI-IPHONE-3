import Foundation

/// AI rewrite / answer actions for the keyboard.
enum KeyboardAIAction: String, CaseIterable, Identifiable {
    case improve
    case complete
    case punctuate
    case shorten
    case longer
    case answer
    case friendlier
    case professional
    case translate
    case summarize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .improve: return "Verbessern"
        case .complete: return "Satz"
        case .punctuate: return "Satzzeichen"
        case .shorten: return "Kürzer"
        case .longer: return "Länger"
        case .answer: return "Antwort"
        case .friendlier: return "Freundlicher"
        case .professional: return "Professionell"
        case .translate: return "Übersetzen"
        case .summarize: return "Zusammenfassen"
        }
    }

    var systemImage: String {
        switch self {
        case .improve: return "checkmark.circle"
        case .complete: return "text.append"
        case .punctuate: return "textformat.abc"
        case .shorten: return "arrow.down.right.and.arrow.up.left"
        case .longer: return "arrow.up.left.and.arrow.down.right"
        case .answer: return "questionmark.circle.fill"
        case .friendlier: return "face.smiling"
        case .professional: return "briefcase"
        case .translate: return "globe"
        case .summarize: return "text.justify.left"
        }
    }

    var isPrimary: Bool { self == .improve }
    var isAnswer: Bool { self == .answer }
    var isComplete: Bool { self == .complete }

    /// Short label stored in the Tastatur chat log (not the full system prompt).
    func displayLabel(for text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let clip = t.count > 72 ? String(t.prefix(72)) + "…" : t
        return "\(title): \(clip)"
    }

    /// Absolute rule for rewrite actions — never Q&A (except `.answer` / `.complete`).
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

            Aufgabe „Verbessern“ — du bist ein sorgfältiger Lektor, kein Autor neuer Inhalte.
            Schau dir den TEXT genau an und aktualisiere NUR das, was wirklich verbessert werden muss:

            1) Rechtschreibung und Tippfehler
            2) Grammatik und Zeichensetzung
            3) Stolpernde / unklare Formulierungen leicht klarer machen — gleiche Aussage
            4) Groß-/Kleinschreibung und Leerzeichen

            Regeln:
            - Was schon gut ist: unverändert lassen.
            - Meinung, Fakten, Fragen und Kernaussage bleiben GLEICH.
            - Keine neuen Infos, kein Umschreiben „schöner um jeden Preis“.
            - Länge etwa gleich (±15%). Keine längere Fassung.
            - Wenn der Text eine Frage ist, bleibt es eine Frage — beantworte sie NICHT.
            - Antworte nur mit dem verbesserten Text.

            TEXT:
            \(t)
            """
        case .complete:
            return """
            Du bist ein Satz-Ergänzer für die Tastatur — kein Chatbot.
            Der TEXT ist ein unvollständiges Fragment / Stichworte. Formuliere daraus einen natürlichen, fertigen Satz.
            Sprache des Fragments behalten (Deutsch oder Englisch).
            Ergänze sinnvolle, wahrscheinliche Details (wer/was/wann), aber keine lange Geschichte.
            Maximal 1–2 kurze Sätze. Kein Intro, kein Markdown, keine Anführungszeichen um den ganzen Satz.

            Beispiele:
            TEXT: Treffen morgen
            RICHTIG: Wir treffen uns morgen.
            TEXT: Meet tomorrow
            RICHTIG: I'll meet you tomorrow.
            TEXT: muss noch einkaufen
            RICHTIG: Ich muss noch einkaufen gehen.

            TEXT:
            \(t)
            """
        case .punctuate:
            return """
            \(rewriterRule)
            Aufgabe: Korrigiere NUR Satzzeichen, Groß-/Kleinschreibung und offensichtliche Tippfehler.
            Inhalt und Wortwahl bleiben gleich. Keine Umformulierung, keine Antwort auf Fragen.

            TEXT:
            \(t)
            """
        case .shorten:
            return """
            \(rewriterRule)
            \(example)
            Aufgabe: Kürze denselben Text RADIKAL — Ziel ca. 30–45% der Original-Länge (deutlich kürzer!).
            Behalte die Kernaussage / Frage. Wenn es eine Frage ist: kürze die Frage, beantworte sie nicht.
            Keine Floskeln.

            TEXT:
            \(t)
            """
        case .longer:
            return """
            \(rewriterRule)
            Aufgabe: Erweitere denselben Text klar (mehr Fluss, 1–3 sinnvolle Details), ohne die Aussage zu ändern.
            Wenn es eine Frage ist: formuliere die Frage ausführlicher — beantworte sie nicht.
            Etwa 140–180% der Länge.

            TEXT:
            \(t)
            """
        case .answer:
            return """
            Du beantwortest eine Frage knapp und klar auf Deutsch (oder in der Sprache der Frage).
            Format — GENAU so, nichts anderes:

            \(t)

            <kurze klare Antwort in 1–3 Sätzen>

            Regeln:
            - Die Originalfrage bleibt in der ersten Zeile/Zeilen EXAKT erhalten (nur minimale Rechtschreibkorrektur erlaubt).
            - Dann eine Leerzeile, dann die Antwort.
            - Kein „Gerne“, kein Intro, kein Markdown, keine Aufzählung außer nötig.
            - Kurz und direkt.
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

        if action == .answer {
            if !s.lowercased().contains(orig.lowercased().prefix(min(24, orig.count))) {
                s = "\(orig)\n\n\(s)"
            }
            return s
        }

        if action == .complete {
            // Keep short completions; drop chatter after first 2 sentences if runaway
            let maxLen = max(48, orig.count * 6 + 40)
            if s.count > maxLen {
                let endMarks: Set<Character> = [".", "!", "?", "。", "！", "？"]
                var cuts = 0
                var end = s.endIndex
                for (i, ch) in s.enumerated() {
                    if endMarks.contains(ch) {
                        cuts += 1
                        if cuts >= 2 {
                            end = s.index(s.startIndex, offsetBy: i + 1)
                            break
                        }
                    }
                }
                s = String(s[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return s
        }

        // Improve / punctuate / tone: reject inflated “answers” — stay close to original
        if action == .improve || action == .punctuate || action == .friendlier || action == .professional {
            let factor = action == .punctuate ? 1.12 : 1.25
            let maxLen = max(orig.count + 12, Int(Double(orig.count) * factor) + 6)
            if s.count > maxLen {
                let endMarks: [Character] = [".", "?", "!", "。", "？", "！"]
                if let idx = s.firstIndex(where: { endMarks.contains($0) }) {
                    let first = String(s[...idx]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if first.count <= maxLen, first.count >= max(3, orig.count / 3) {
                        s = first
                    } else {
                        s = origIsQuestion ? polishQuestionFallback(orig) : orig
                    }
                } else {
                    s = orig
                }
            }
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
            let maxLen = max(6, Int(Double(orig.count) * 0.5) + 4)
            if s.count > orig.count + 12 {
                if origIsQuestion {
                    s = polishQuestionFallback(orig)
                } else {
                    s = String(s.prefix(maxLen)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else if s.count > maxLen + 20 {
                s = String(s.prefix(maxLen)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if action == .longer {
            if origIsQuestion {
                let outIsQuestion = s.contains("?") || s.contains("？")
                if !outIsQuestion, s.count > orig.count + 30 {
                    s = polishQuestionFallback(orig)
                }
            }
        }
        return s
    }

    private static func polishQuestionFallback(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return t }
        let first = t.prefix(1).uppercased()
        let rest = String(t.dropFirst())
        t = first + rest
        if !t.hasSuffix("?"), !t.hasSuffix("？") {
            t += "?"
        }
        return t
    }
}
