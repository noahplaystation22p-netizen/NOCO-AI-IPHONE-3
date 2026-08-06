import Foundation

/// AI rewrite / answer actions for the keyboard.
enum KeyboardAIAction: String, CaseIterable, Identifiable {
    case improve
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

    /// Absolute rule for rewrite actions — never Q&A (except `.answer` / `.complete`).
    private var rewriterRule: String {
        """
        Du bist ein Text-Korrektor / Umformulierer — KEIN Chatbot und KEIN Wissensassistent.
        Der Text unter TEXT ist zu BEARBEITEN, auch wenn er wie eine Frage aussieht.
        VERBOTEN: die Frage beantworten, erklären, definieren, Tipps geben, Wissen hinzufügen,
        Begrüßung, Intro, Markdown-Wrapper, Anführungszeichen um den ganzen Text, „Gerne“, „Hier ist“, „Das bedeutet“.
        Antworte AUSSCHLIESSLICH mit dem fertigen Ergebnistext — nichts sonst.
        """
    }

    func prompt(for text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let example = """
        Beispiel (nur Korrektur/Umformung, KEINE Antwort):
        TEXT: was ist ein Duft?
        RICHTIG: Was ist ein Duft?
        FALSCH: Ein Duft ist ein Geruch / Aroma …
        """
        switch self {
        case .improve:
            return """
            \(rewriterRule)
            \(example)

            Aufgabe „Verbessern“ — Hauptfunktion der Tastatur. Du bist ein erstklassiger Lektor und Schreib-Assistent.

            Der TEXT ist oft Diktat / gesprochene Sprache: holprig, ohne Absätze, „äh“, Wiederholungen.
            Deine Aufgabe: daraus einen klaren, fertigen Text machen, den man so absenden kann.

            Analysiere zuerst:
            - Absicht (Nachricht, Glückwunsch, Notiz, Frage, E-Mail …)
            - Welche Gedanken / Infos stecken drin (auch wenn chaotisch)?

            Dann schreibe den Text NEU und STRUKTURIERT auf:
            1) Sinnvolle Absätze (Begrüßung / Kern / Detail / Abschluss — nur was passt)
            2) Rechtschreibung, Grammatik, Satzzeichen — fehlende Anführungszeichen („…“) setzen
            3) Holpriges Diktat in natürliche Sätze gießen — gleiche Aussage, klarer Ton
            4) Doppeltes streichen, Füllwörter („richtig richtig“, „irgendwie“) reduzieren
            5) Groß-/Kleinschreibung und Leerzeichen

            Beispiel Diktat → Ergebnis:
            TEXT: ey ich freu mich so auf deinen geburtstag das wär echt mega cool weiß noch nicht ob ich was mitbringen soll lg
            RICHTIG:
            Hey!

            Ich freue mich richtig auf deinen Geburtstag — das wird mega cool.

            Ich weiß noch nicht, ob ich etwas mitbringen soll.

            LG

            Harte Regeln:
            - Bedeutung und Infos bleiben — nichts erfinden, nichts weglassen was inhaltlich zählt.
            - Keine Antwort auf Fragen im Text, kein Wissen ergänzen.
            - Wenn es eine Frage ist: bleibe eine (klare) Frage — oder strukturierte Nachricht die die Frage enthält.
            - Nicht den ganzen Text in Anführungszeichen packen.
            - Ausgabe = nur der fertige Text, bereit zum Einfügen (mit Absätzen wo sinnvoll).

            TEXT:
            \(t)
            """
        case .complete:
            return """
            Aufgabe: SATZERGÄNZUNG — aus dem Fragment GENAU EINEN fertigen Satz machen.

            Regeln (streng):
            - Ausgabe = NUR dieser eine Satz. Nichts davor, nichts danach.
            - Kein zweiter Satz, kein Absatz, keine Liste, kein Markdown.
            - Kein Intro („Gerne“, „Hier ist“, „Klar“), keine Anführungszeichen um den Satz.
            - Sprache des Fragments behalten (DE oder EN).
            - Sinnvolle, kurze Ergänzung (wer/was/wann) — aber keine Geschichte.
            - Endet mit Punkt (oder !/? wenn passend).

            Beispiele:
            TEXT: Treffen morgen
            RICHTIG: Wir treffen uns morgen.
            FALSCH: Wir treffen uns morgen. Ich freue mich schon!
            TEXT: Meet tomorrow
            RICHTIG: I'll meet you tomorrow.
            TEXT: muss noch einkaufen
            RICHTIG: Ich muss noch einkaufen gehen.

            TEXT:
            \(t)
            """
        case .list:
            return """
            \(rewriterRule)

            Aufgabe „Liste“ — wandle den TEXT in eine klare Aufzählung mit Punkten um.

            Regeln:
            - Jeder sinnvolle Punkt / Gedanke / Aufgabe / Gegenstand wird ein eigener Listenpunkt.
            - Format GENAU so (eine Zeile pro Punkt, Bindestrich + Leerzeichen):
              - Punkt eins
              - Punkt zwei
              - Punkt drei
            - Keine Nummerierung (1. 2. 3.), kein Markdown mit Sternchen, keine Überschrift, kein Intro.
            - Inhalt und Bedeutung behalten — nur strukturieren, nicht erfinden.
            - Kurze, knackige Formulierungen pro Zeile.
            - Wenn der Text schon eine Liste ist: bereinigen und vereinheitlichen.
            - Sprache des Originals behalten.

            TEXT:
            \(t)
            """
        case .punctuate:
            return """
            \(rewriterRule)

            Aufgabe „Satzzeichen“ — korrigiere Zeichensetzung und Schreibweise, ohne umzuformulieren.

            Erlaubt:
            - Punkte, Kommas, Frage-/Ausrufezeichen, Doppelpunkte, Semikolons
            - Fehlende Anführungszeichen („…“ / "…") und Apostrophe setzen, wo der Sinn sie braucht
            - Groß-/Kleinschreibung am Satzanfang
            - Offensichtliche Tippfehler nur wenn klar

            Verboten:
            - Wörter austauschen oder Sätze umschreiben
            - Inhalt ändern oder Fragen beantworten
            - Den ganzen Text in Anführungszeichen setzen

            TEXT:
            \(t)
            """
        case .shorten:
            return """
            \(rewriterRule)
            \(example)

            Aufgabe „Kürzer“ — RADIKAL kürzen, aber nichts Wichtiges verlieren.

            Ziel-Länge: ca. 20–35% des Originals (deutlich, spürbar kürzer — nicht nur ein bisschen).

            So gehst du vor:
            1) Alle Kerninfos / Fakten / die eigentliche Aussage behalten
            2) Alles Füllmaterial streichen: Wiederholungen, Füllwörter, Höflichkeits-Schleifen, Nebensätze ohne Mehrwert
            3) Mehrere Sätze zu einem knappen Satz verschmelzen, wo möglich
            4) Natürlicher Ton, gleiche Sprache — klingt nicht abgehackt oder „schlechter“
            5) Wenn es eine Frage ist: kürze die Frage — beantworte sie nicht

            Beispiel:
            TEXT: Hey, also ich wollte dir eigentlich nur kurz schreiben, dass ich mich echt mega auf deinen Geburtstag freue, das wird bestimmt total cool, und ich weiß halt noch nicht so ganz, ob ich irgendwas mitbringen soll, lg
            RICHTIG: Hey, freue mich auf deinen Geburtstag! Weiß noch nicht, ob ich was mitbringe. LG

            Ausgabe = nur der kurze Text.

            TEXT:
            \(t)
            """
        case .longer:
            return """
            \(rewriterRule)

            Aufgabe „Länger“ — erweitere denselben Text klar und nützlich, ohne die Aussage zu verdrehen.

            Ziel:
            - Ca. 140–180% der Original-Länge.
            - Mehr Fluss: vollständige Sätze, sanfte Übergänge, 1–3 sinnvolle Details die schon im Text angelegt sind.
            - Keine neuen Fakten erfinden, die nicht aus dem Original folgen.
            - Wenn es eine Frage ist: formuliere die Frage ausführlicher und klarer — beantworte sie nicht.
            - Gleicher Ton und gleiche Sprache.
            - Ausgabe = nur der längere Text.

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

            Aufgabe „Freundlicher“ — gleicher Inhalt, wärmerer Ton.
            - Höflicher, einladender, menschlicher — ohne kitschig zu werden.
            - Ungefähr gleiche Länge (±20%).
            - Keine Antwort auf den Inhalt, keine neuen Infos.
            - Wenn es eine Frage ist: bleibe eine freundlichere Frage.

            TEXT:
            \(t)
            """
        case .professional:
            return """
            \(rewriterRule)

            Aufgabe „Professionell“ — gleicher Inhalt, formeller Business-Ton.
            - Klar, höflich, präzise — wie in einer guten E-Mail.
            - Ungefähr gleiche Länge (±20%).
            - Keine Antwort auf den Inhalt, keine neuen Infos.
            - Wenn es eine Frage ist: bleibe eine professionellere Frage.

            TEXT:
            \(t)
            """
        case .translate:
            return """
            \(rewriterRule)

            Aufgabe „Übersetzen“ — EN↔DE (oder erkenne die Zielsprache aus dem Kontext).
            - Nur die Übersetzung, keine Erklärung, kein Wörterbuch-Kommentar.
            - Ton und Register möglichst beibehalten.
            - Wenn es eine Frage ist: übersetze die Frage, beantworte sie nicht.
            - Fehlende Anführungszeichen in der Zielsprache korrekt setzen.

            TEXT:
            \(t)
            """
        case .summarize:
            return """
            \(rewriterRule)

            Aufgabe „Zusammenfassen“ — Komprimat des TEXTES in 1–2 kurzen Sätzen.
            - Nur was im Text steht — keine neue Antwort, keine Meinung.
            - Klar und vollständig genug, dass die Kernaussage bleibt.
            - Keine Aufzählung, kein Intro.

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
            // Exactly one sentence — strip chatter and extra sentences
            let endMarks: Set<Character> = [".", "!", "?", "。", "！", "？"]
            if let idx = s.firstIndex(where: { endMarks.contains($0) }) {
                s = String(s[...idx]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let nl = s.firstIndex(of: "\n") {
                s = String(s[..<nl]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // Soft length cap so models don't write essays
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
            // Normalize bullets to "- " lines; drop empty chatter lines
            let rawLines = s.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
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
                if !l.hasPrefix("- ") {
                    l = "- \(l)"
                }
                return l
            }
            if !cleaned.isEmpty {
                s = cleaned.joined(separator: "\n")
            }
            return s
        }

        // Improve / punctuate / tone: reject inflated “answers” — stay close to original
        if action == .improve || action == .punctuate || action == .friendlier || action == .professional {
            // Improve may add paragraph breaks for dictation → allow more room
            let factor: Double = {
                switch action {
                case .improve: return orig.count > 120 ? 2.2 : 1.6
                case .punctuate: return 1.12
                default: return 1.25
                }
            }()
            let maxLen = max(orig.count + 24, Int(Double(orig.count) * factor) + 12)
            if s.count > maxLen {
                // Prefer keeping structured multi-paragraph improve output when it's not a Q&A dump
                let paragraphCount = s.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
                if action == .improve, paragraphCount >= 2, s.count < orig.count * 3 + 80, !looksLikeAnswerDump(s, original: orig) {
                    // keep
                } else {
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
            // Expect ~20–40% length; if model barely shortened, keep its attempt if still under 55%
            let hardMax = max(8, Int(Double(orig.count) * 0.55) + 6)
            let idealMax = max(6, Int(Double(orig.count) * 0.38) + 4)
            if s.count > orig.count + 8 {
                // Model answered / expanded — reject
                s = origIsQuestion ? polishQuestionFallback(orig) : String(orig.prefix(idealMax))
            } else if s.count > hardMax {
                s = String(s.prefix(idealMax)).trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// Detect model answering instead of rewriting (e.g. definitions).
    private static func looksLikeAnswerDump(_ s: String, original: String) -> Bool {
        let lower = s.lowercased()
        let banned = ["das bedeutet", "kurz gesagt", "zusammengefasst", "die antwort", "hier ist die"]
        if banned.contains(where: { lower.hasPrefix($0) || lower.contains("\n\n\($0)") }) { return true }
        let origQ = original.contains("?") || original.lowercased().hasPrefix("was ")
        if origQ, !s.contains("?"), s.count > original.count + 40 { return true }
        return false
    }
}
