import Foundation

/// Decides whether the Agent should ask clarifying questions before planning.
enum AgentIntake {
    /// Returns 1–3 targeted questions, or nil when the Agent can start immediately.
    static func clarifyingQuestions(for goal: String) -> [String]? {
        let t = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 12 else { return nil }
        let lower = t.lowercased()

        // Simple / self-contained → no questions
        if isSimple(lower) { return nil }

        var questions: [String] = []

        if matches(lower, #"\b(ausflug|reise|strand|urlaub|wochenende|fahrt|trip)\b"#) {
            if !matches(lower, #"\b(von|ab|start|aus)\b.+\b(nach|nach)\b"#)
                && !matches(lower, #"\b(berlin|hamburg|münchen|köln|frankfurt|stuttgart|düsseldorf)\b"#) {
                questions.append("Von welchem Ort startest du?")
            }
            if !matches(lower, #"\b(bahn|zug|auto|flug|bus|fahrrad|zu fuß|öffentliche)\b"#) {
                questions.append("Möchtest du mit der Bahn, dem Auto oder anders fahren?")
            }
            if !matches(lower, #"\b(wetter|fahrzeit|fahrplan|budget|kosten)\b"#) {
                questions.append("Soll ich Wetter und Fahrzeiten berücksichtigen?")
            }
        } else if matches(lower, #"\b(website|webseite|app|projekt|workflow|automat|orga|plane|planen|organisiere)\b"#) {
            if !matches(lower, #"\b(deadline|bis |termin|heute|morgen|woche)\b"#) {
                questions.append("Bis wann soll das fertig sein?")
            }
            if !matches(lower, #"\b(ziel|nutzer|kunde|für mich|privat|arbeit)\b"#) {
                questions.append("Für wen oder welchen Zweck ist das gedacht?")
            }
            if questions.count < 2, !matches(lower, #"\b(priorität|wichtig|muss|optional)\b"#) {
                questions.append("Was ist dir am wichtigsten am Ergebnis?")
            }
        } else if matches(lower, #"\b(kauf|bestell|suche|vergleiche|empfehl)\b"#) {
            if !matches(lower, #"\b(€|euro|budget|preis|günstig|max)\b"#) {
                questions.append("Welches Budget hast du?")
            }
            if !matches(lower, #"\b(marke|modell|größe|farbe)\b"#) {
                questions.append("Gibt es Marken oder Anforderungen, die wichtig sind?")
            }
        } else if isComplex(lower) {
            questions.append("Was ist das wichtigste Ergebnis für dich?")
            if !matches(lower, #"\b(heute|morgen|woche|bald|sofort)\b"#) {
                questions.append("In welchem Zeitrahmen soll ich denken?")
            }
        }

        let unique = questions.reduce(into: [String]()) { acc, q in
            if !acc.contains(q) { acc.append(q) }
        }
        let clipped = Array(unique.prefix(3))
        return clipped.isEmpty ? nil : clipped
    }

    private static func isSimple(_ t: String) -> Bool {
        if matches(t, #"^(was ist|wer ist|erkläre|übersetze|fasse|kürze|korrigiere|rechne|wie spät)"#) {
            return true
        }
        if matches(t, #"\b(ja oder nein|kurz sagen|eine zeile)\b"#) { return true }
        // Short factual asks without planning verbs
        if t.count < 55, !matches(t, #"\b(plane|organisiere|baue|erstelle|recherchiere|vergleiche|hilf mir bei)\b"#) {
            return true
        }
        return false
    }

    private static func isComplex(_ t: String) -> Bool {
        matches(t, #"\b(plane|organisiere|baue|erstelle|recherchiere|mehrere|schritt|projekt|strategie|komplett)\b"#)
            || t.count > 120
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
