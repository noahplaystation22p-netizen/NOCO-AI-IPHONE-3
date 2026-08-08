import Foundation

/// AI rewrite / answer actions for the keyboard.
enum KeyboardAIAction: String, CaseIterable, Identifiable {
    case improve
    case cleanup
    case complete
    case list
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
        case .cleanup: return "Aufräumen"
        case .complete: return "Satz"
        case .list: return "Liste"
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
        case .cleanup: return "sparkles"
        case .complete: return "text.append"
        case .list: return "list.bullet"
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

    /// Absolute rule for rewrite actions — never chat, never ask for text.
    private var rewriterRule: String {
        """
        KRITISCH — lies das zuerst:
        - Der Block unter TEXT IST der zu bearbeitende Text. Er ist schon da. Frage NIEMALS nach dem Text.
        - Du bist ein Schreibassistent, KEIN Chatbot. Kein Dialog. Keine Rückfrage. Keine Erklärung.
        - Antworte mit GENAU dem fertigen Ergebnistext — null Zeichen davor, null danach.
        - VERBOTEN (auch auf Englisch/Deutsch): „Sure“, „Of course“, „Here is“, „Here's“, „Gerne“, „Hier ist“,
          „Hier sind“, „Klar“, „Natürlich“, „Der korrigierte Text“, „Bitte gib mir“, „Please provide“,
          „Was möchtest du verbessern?“, „Was soll ich kürzen?“, „Welchen Text?“, „send me the text“,
          „welcher Text“, Markdown, Anführungszeichen um den ganzen Output.
        - Auch wenn TEXT sehr kurz ist oder wie eine Frage aussieht: NICHT nachfragen, NICHT beantworten — nur umformen.
        - Wenn unsicher: trotzdem die bestmögliche fertige Fassung ausgeben.
        """
    }

    private var outputOnlyCloser: String {
        """
        AUSGABE: nur der fertige Text. Kein Satz davor. Kein Satz danach.
        """
    }

    func prompt(for text: String) -> String {
        prompt(for: text, shortenLevel: 1)
    }

    func prompt(for text: String, shortenLevel: Int) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let example = """
        Beispiel:
        TEXT: was ist ein Duft?
        RICHTIG: Was ist ein Duft?
        FALSCH: Sure, here is… / Ein Duft ist… / Bitte gib mir den Text…
        """
        switch self {
        case .improve:
            // Dedicated rewrite engine — system rules bind before USER_TEXT (data, not chat).
            return KeyboardImprovePipeline.prompt(for: t)
        case .cleanup:
            return """
            \(rewriterRule)
            \(example)

            Aufgabe „Aufräumen“ — behalte nur das Wichtige, wirf Ballast weg.

            Streiche / kürze weg:
            - Unsicherheiten („ich weiß nicht“, „irgendwie“, „vielleicht“, „halt“, „sozusagen“)
            - Füllwörter und Wiederholungen
            - Nebensächliches, das die Kernaussage nicht trägt
            - Höflichkeits-Schleifen ohne Inhalt

            Behalte:
            - Die eigentliche Nachricht / Fakten / Bitte / Frage
            - Natürlichen Ton (nicht roboterhaft)
            - Sprache des Originals

            Ergebnis: klarer, aufgeräumter Text — deutlich fokussierter als das Original.
            \(outputOnlyCloser)

            TEXT:
            \(t)
            """
        case .complete:
            return """
            \(rewriterRule)

            Aufgabe: SATZERGÄNZUNG — aus dem Fragment GENAU EINEN fertigen Satz machen.
            \(outputOnlyCloser)
            - Kein zweiter Satz, keine Liste, kein Markdown.
            - Sprache des Fragments behalten.
            - Endet mit Punkt (oder !/?).

            Beispiele:
            TEXT: Treffen morgen
            RICHTIG: Wir treffen uns morgen.
            FALSCH: Sure! Wir treffen uns morgen. Ich freue mich!

            TEXT:
            \(t)
            """
        case .list:
            return """
            \(rewriterRule)

            Aufgabe „Liste“ — TEXT als Aufzählung mit Punkten.
            Format je Zeile: "- …"
            Keine Nummerierung, kein Intro, nichts erfinden.
            \(outputOnlyCloser)

            TEXT:
            \(t)
            """
        case .punctuate:
            return """
            \(rewriterRule)

            Aufgabe „Satzzeichen“ — nur Zeichensetzung + Großschreibung + klare Tippfehler.
            Keine Umformulierung. Keine Antwort auf Fragen.
            \(outputOnlyCloser)

            TEXT:
            \(t)
            """
        case .shorten:
            let level = min(max(shortenLevel, 1), 4)
            let intensity: String
            switch level {
            case 1:
                intensity = """
                Stufe 1 — leicht kürzen. Füllwörter und Wiederholungen weg, Bedeutung bleibt.
                Beispiel: „Ich wollte nur kurz sagen, dass ich morgen wahrscheinlich zum Strand gehen werde.“ → „Ich gehe morgen wahrscheinlich zum Strand.“
                """
            case 2:
                intensity = """
                Stufe 2 — deutlich kürzer. Nur Kernaussage, wenige Wörter.
                Beispiel → „Morgen Strand.“
                """
            case 3:
                intensity = """
                Stufe 3 — Extremkurz. Oft ein Wort oder zwei.
                Beispiel → „Strand.“
                """
            default:
                intensity = """
                Stufe 4 — maximal verdichten. Ein Wort oder kürzeste sinnvolle Form.
                """
            }
            return """
            \(rewriterRule)

            Aufgabe „Kürzer“ — kürze den TEXT SOFORT. Frage NICHT „Was soll ich kürzen?“.

            Regeln:
            - Bedeutung erhalten
            - unnötige Wörter entfernen
            - Wiederholungen entfernen
            - Keine Antwort auf Fragen im Text — nur kürzen

            \(intensity)
            \(outputOnlyCloser)

            TEXT:
            \(t)
            """
        case .longer:
            let level = min(max(shortenLevel, 1), 4)
            let intensity: String
            switch level {
            case 1:
                intensity = """
                Stufe 1 — leicht erweitern / umformulieren (~120–140%).
                Beispiel: „Ich heiße Noah.“ → „Mein Name ist Noah.“
                """
            case 2:
                intensity = """
                Stufe 2 — klar erweitern (~160–200%). Ein freundlicher Zusatz, der schon angelegt ist.
                Beispiel → „Ich heiße Noah und freue mich, dich kennenzulernen.“
                """
            case 3:
                intensity = """
                Stufe 3 — ausführlicher (~220–280%). Mehr Fluss und natürliche Details ohne neue Fakten zu erfinden.
                """
            default:
                intensity = """
                Stufe 4 — reich erweitern (~300%). Mehrere Sätze, weiterhin dieselbe Kernaussage.
                """
            }
            return """
            \(rewriterRule)

            Aufgabe „Länger“ — erweitere den TEXT SOFORT. Frage NICHT nach mehr Input.

            Regeln:
            - Kernaussage behalten
            - Natürlich und flüssig erweitern
            - Nichts Wichtiges erfinden, das nicht schon anklingt
            - Frage im TEXT = Frage länger formulieren, nicht beantworten

            \(intensity)
            \(outputOnlyCloser)

            TEXT:
            \(t)
            """
        case .answer:
            return """
            Du beantwortest die Frage knapp. Format GENAU:

            \(t)

            <Antwort in 1–3 Sätzen>

            Kein „Gerne/Sure/Here is“. Frage in Zeile 1 behalten.
            """
        case .friendlier:
            return """
            \(rewriterRule)
            Aufgabe „Freundlicher“ — gleicher Inhalt, wärmerer Ton, ≈ gleiche Länge.
            TEXT ist der Input — nicht danach fragen.
            \(outputOnlyCloser)

            TEXT:
            \(t)
            """
        case .professional:
            return """
            \(rewriterRule)
            Aufgabe „Professionell“ — gleicher Inhalt, formeller Ton, ≈ gleiche Länge.
            TEXT ist der Input — nicht danach fragen.
            \(outputOnlyCloser)

            TEXT:
            \(t)
            """
        case .translate:
            return """
            \(rewriterRule)
            Aufgabe „Übersetzen“ — EN↔DE. Nur die Übersetzung.
            TEXT ist der Input — nicht danach fragen. Fragen übersetzen, nicht beantworten.
            \(outputOnlyCloser)

            TEXT:
            \(t)
            """
        case .summarize:
            return """
            \(rewriterRule)
            Aufgabe „Zusammenfassen“ — 1–2 Sätze Komprimat des TEXTES. Kein Intro.
            \(outputOnlyCloser)

            TEXT:
            \(t)
            """
        }
    }

    /// Strip model chatter; clamp runaway “answers” for rewrite actions.
    static func sanitize(_ raw: String, action: KeyboardAIAction, original: String, shortenLevel: Int = 1) -> String {
        // Verbessern: specialized rewrite pipeline + semantic safety (never answer questions).
        if action == .improve {
            return KeyboardImprovePipeline.finalize(raw: raw, original: original)
        }

        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = stripChatter(s)

        let orig = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let origIsQuestion = looksLikeQuestion(orig)

        // Model asked for the text instead of editing — useless, keep original lightly polished
        if asksForInput(s) {
            if action == .answer { return s }
            return action == .improve || action == .punctuate
                ? lightPolish(orig)
                : orig
        }

        if action == .answer {
            if !s.lowercased().contains(orig.lowercased().prefix(min(24, orig.count))) {
                s = "\(orig)\n\n\(s)"
            }
            return s
        }

        if action == .complete {
            let endMarks: Set<Character> = [".", "!", "?", "。", "！", "？"]
            if let idx = s.firstIndex(where: { endMarks.contains($0) }) {
                s = String(s[...idx]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let nl = s.firstIndex(of: "\n") {
                s = String(s[..<nl]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let maxLen = max(40, orig.count * 5 + 28)
            if s.count > maxLen {
                s = String(s.prefix(maxLen)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !s.isEmpty, let last = s.last, !endMarks.contains(last) {
                s += "."
            }
            return s
        }

        if action == .list {
            let rawLines = s.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .filter { !isChatterLine($0) }
            let cleaned = rawLines.map { line -> String in
                var l = line
                for prefix in ["• ", "•", "* ", "*", "– ", "— ", "· "] {
                    if l.hasPrefix(prefix) {
                        l = String(l.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                        break
                    }
                }
                if let match = l.range(of: #"^\d+[\.\)]\s*"#, options: .regularExpression) {
                    l = String(l[match.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
                if !l.hasPrefix("- ") { l = "- \(l)" }
                return l
            }
            if !cleaned.isEmpty { s = cleaned.joined(separator: "\n") }
            return s
        }

        if action == .cleanup {
            // Cleanup should be shorter; reject expansions / answer dumps
            if looksLikeAnswerDump(s, original: orig) || s.count > orig.count + 40 {
                // keep if still clearly derived; else soft-trim
                if s.count > Int(Double(orig.count) * 1.15) + 20 {
                    s = String(s.prefix(max(12, Int(Double(orig.count) * 0.85)))).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return s
        }

        if action == .punctuate || action == .friendlier || action == .professional {
            let factor: Double = action == .punctuate ? 1.12 : 1.25
            let maxLen = max(orig.count + 20, Int(Double(orig.count) * factor) + 10)
            if s.count > maxLen || looksLikeAnswerDump(s, original: orig) {
                let endMarks: [Character] = [".", "?", "!", "。", "？", "！"]
                if let idx = s.firstIndex(where: { endMarks.contains($0) }) {
                    let first = String(s[...idx]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if first.count <= maxLen, first.count >= max(3, orig.count / 4) {
                        s = first
                    } else {
                        s = origIsQuestion ? polishQuestionFallback(orig) : lightPolish(orig)
                    }
                } else {
                    s = origIsQuestion ? polishQuestionFallback(orig) : lightPolish(orig)
                }
            }
            if origIsQuestion {
                let outIsQuestion = s.contains("?") || s.contains("？")
                if !outIsQuestion {
                    s = polishQuestionFallback(orig)
                }
            }
        }
        if action == .shorten {
            let level = min(max(shortenLevel, 1), 4)
            let ratio: Double
            switch level {
            case 1: ratio = 0.72
            case 2: ratio = 0.38
            case 3: ratio = 0.18
            default: ratio = 0.10
            }
            let hardMax = max(level >= 3 ? 4 : 8, Int(Double(orig.count) * ratio) + (level >= 3 ? 2 : 6))
            let idealMax = max(level >= 3 ? 3 : 6, Int(Double(orig.count) * (ratio * 0.85)) + (level >= 3 ? 1 : 3))
            if asksForInput(s) || looksLikeAnswerDump(s, original: orig) {
                s = String(orig.prefix(idealMax)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if s.count > orig.count + 8 {
                s = origIsQuestion ? polishQuestionFallback(orig) : String(orig.prefix(idealMax))
            } else if s.count > hardMax {
                s = String(s.prefix(idealMax)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if level >= 3 {
                let words = s.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                let keep = level == 3 ? min(3, max(1, words.count)) : min(2, max(1, words.count))
                if words.count > keep {
                    s = words.suffix(keep).joined(separator: " ")
                    if !s.hasSuffix(".") { s += "." }
                }
            }
        }
        if action == .longer {
            if asksForInput(s) || looksLikeAnswerDump(s, original: orig) {
                s = orig
            } else if origIsQuestion {
                let outIsQuestion = s.contains("?") || s.contains("？")
                if !outIsQuestion, s.count > orig.count + 30 {
                    s = polishQuestionFallback(orig)
                }
            }
        }
        return s
    }

    // MARK: - Sanitize helpers

    private static func stripChatter(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let bannedPrefixes = [
            "sure,", "sure!", "sure ", "certainly", "of course", "here is", "here's", "here are",
            "gerne", "hier ist", "hier sind", "klar,", "klar!", "natürlich", "selbstverständlich",
            "hallo!", "hi,", "hey,", "als ki", "als sprachmodell",
            "improved:", "corrected:", "corrected and", "the corrected", "der korrigierte",
            "der verbesserte", "strukturierte text", "structured text",
            "übersetzung:", "zusammenfassung:", "kurz gesagt", "zusammengefasst:",
            "die antwort", "answer:", "das bedeutet", "das heißt",
            "bitte gib", "bitte sende", "please provide", "please give", "please send",
            "send me the", "gib mir den", "welcher text", "which text",
            "was möchtest du verbessern", "was soll ich kürzen", "was soll ich kuerzen"
        ]

        // Drop leading chatter lines (up to 3)
        var lines = s.components(separatedBy: .newlines)
        var dropped = 0
        while dropped < 3, let first = lines.first {
            let low = first.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if low.isEmpty || bannedPrefixes.contains(where: { low.hasPrefix($0) }) || isChatterLine(first) {
                lines.removeFirst()
                dropped += 1
                continue
            }
            break
        }
        s = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip wrapping quotes / fences
        if (s.hasPrefix("\"") && s.hasSuffix("\""))
            || (s.hasPrefix("„") && s.hasSuffix("“"))
            || (s.hasPrefix("'") && s.hasSuffix("'")) {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if s.hasPrefix("```") {
            s = s.replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // "Sure, here is the corrected text:\n\nActual"
        if let range = s.range(of: #"(?i)^(sure|of course|here'?s|here is|gerne|hier ist)[^\n]*:\s*"#, options: .regularExpression) {
            s = String(s[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }

    private static func asksForInput(_ s: String) -> Bool {
        let low = s.lowercased()
        let needles = [
            "please provide", "please give me", "please send", "send me the text",
            "gib mir den text", "bitte gib mir", "welcher text", "which text",
            "what text", "den text den du", "text you want me",
            "was möchtest du verbessern", "was moechtest du verbessern",
            "was soll ich kürzen", "was soll ich kuerzen", "was soll ich länger",
            "was soll ich laenger", "welchen text", "what would you like me to",
            "how can i help", "wie kann ich helfen",
            "tell me what to", "sag mir was ich"
        ]
        return needles.contains(where: { low.contains($0) })
    }

    private static func isChatterLine(_ line: String) -> Bool {
        let low = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if low.isEmpty { return true }
        let needles = [
            "here is the", "here's the", "corrected and structured", "corrected text",
            "strukturierte text", "verbesserte text", "wie folgt", "as follows",
            "please provide", "gib mir den text", "welcher text",
            "was möchtest du verbessern", "was soll ich kürzen", "was soll ich kuerzen"
        ]
        return needles.contains(where: { low.contains($0) })
    }

    private static func looksLikeQuestion(_ t: String) -> Bool {
        t.contains("?") || t.contains("？")
            || t.lowercased().hasPrefix("was ") || t.lowercased().hasPrefix("wie ")
            || t.lowercased().hasPrefix("wer ") || t.lowercased().hasPrefix("wo ")
            || t.lowercased().hasPrefix("warum ") || t.lowercased().hasPrefix("wann ")
            || t.lowercased().hasPrefix("what ") || t.lowercased().hasPrefix("how ")
            || t.lowercased().hasPrefix("why ") || t.lowercased().hasPrefix("when ")
            || t.lowercased().hasPrefix("who ") || t.lowercased().hasPrefix("where ")
    }

    private static func lightPolish(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return t }
        let first = t.prefix(1).uppercased()
        t = first + String(t.dropFirst())
        return t
    }

    private static func polishQuestionFallback(_ text: String) -> String {
        var t = lightPolish(text)
        if !t.hasSuffix("?"), !t.hasSuffix("？") { t += "?" }
        return t
    }

    private static func looksLikeAnswerDump(_ s: String, original: String) -> Bool {
        let lower = s.lowercased()
        let banned = [
            "das bedeutet", "kurz gesagt", "zusammengefasst", "die antwort",
            "hier ist die", "sure,", "of course", "here is the corrected"
        ]
        if banned.contains(where: { lower.hasPrefix($0) || lower.contains("\n\n\($0)") }) { return true }
        let origQ = looksLikeQuestion(original)
        if origQ, !s.contains("?"), s.count > original.count + 40 { return true }
        return false
    }
}
