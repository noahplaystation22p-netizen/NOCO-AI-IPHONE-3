import Foundation

/// User preference for NOCO Live Knowledge (web enrichment).
enum LiveKnowledgePolicy: String, CaseIterable, Identifiable {
    case auto
    case local
    case web

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Automatisch"
        case .local: return "Immer lokal"
        case .web: return "Immer Web"
        }
    }

    var subtitle: String {
        switch self {
        case .auto: return "NOCO entscheidet — lokal zuerst, Web bei aktuellen Fakten"
        case .local: return "Nur lokales Modell, kein Internet"
        case .web: return "Für jede Antwort Web-Kontext holen"
        }
    }

    /// Wire value for Companion `web` field.
    var wireValue: String {
        switch self {
        case .auto: return "auto"
        case .local: return "off"
        case .web: return "on"
        }
    }

    private static let defaultsKey = "nocoai.liveKnowledge"

    static var current: LiveKnowledgePolicy {
        get {
            let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? "auto"
            return LiveKnowledgePolicy(rawValue: raw) ?? .auto
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}

/// Speak-specific Live Knowledge preference (Independent from chat Plus / global when set).
enum SpeakLiveKnowledgePolicy {
    private static let defaultsKey = "nocoai.speakLiveKnowledge"

    static var current: LiveKnowledgePolicy {
        get {
            let raw = UserDefaults.standard.string(forKey: defaultsKey)
            if let raw, let policy = LiveKnowledgePolicy(rawValue: raw) {
                return policy
            }
            // First launch: mirror global Live Knowledge until user sets Speak explicitly.
            return LiveKnowledgePolicy.current
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    static var hasExplicitOverride: Bool {
        UserDefaults.standard.string(forKey: defaultsKey) != nil
    }
}

/// One-shot override from Plus menus (consumed on next send).
enum LiveKnowledgeOnceOverride: String {
    case web
    case local
}

enum LiveKnowledgeRouting {
    /// Detect whether this question likely needs live web data (client-side Auto hint).
    /// Must stay aligned with Companion `decideLiveKnowledge` — local first, LIVE only when needed.
    static func likelyNeedsWeb(_ text: String) -> Bool {
        let t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count < 3 { return false }

        let localOnly = [
            "schreib", "gedicht", "geschichte", "übersetze", "ubersetze", "refaktor",
            "erkläre mir einfach", "erklare mir einfach", "formulier", "witz", "rätsel", "ratsel"
        ]
        let liveNeedles = [
            "aktuell", "nachrichten", "news", "schlagzeile", "breaking", "ticker",
            "wetter", "temperatur", "vorhersage", "wetterbericht",
            "preis", "kostet", "kosten", "bitcoin", "aktie", "kurs", "börse", "boerse",
            "spielstand", "ergebnis", "gewonnen", "verloren", "bundesliga", "champions league",
            "weltmeisterschaft", "europameisterschaft", "spielplan", "nächstes spiel", "naechstes spiel",
            "formel 1", "f1 ", "grand prix",
            "schau nach", "recherchier", "suche im internet", "google", "im web", "online nach",
            "wie viel kostet", "was ist passiert", "was gibt es neues", "neueste",
            "zug ", "bahn ", "fahrplan", "abfahrt", "ankunft",
            "wer spielt", "spielt heute", "heutige spiele",
            "neuerscheinung", "angekündigt", "angekuendigt", "ankündigung", "ankuendigung",
            "in der welt", "weltgeschehen", "was ist gerade", "was passiert gerade",
            "apple news", "dieser woche", "dieses jahr", "heute nacht"
        ]

        let hasLive = liveNeedles.contains(where: { t.contains($0) })
            || t.contains(" wm ") || t.hasPrefix("wm ") || t.hasSuffix(" wm") || t == "wm"
            || t.contains(" em ") || RegexHelpers.containsWord(t, "wm") || RegexHelpers.containsWord(t, "em")
            || t.contains("heute") && (t.contains("nachricht") || t.contains("spiel") || t.contains("passiert") || t.contains("los"))
            || t.contains("gestern") && (t.contains("gewonnen") || t.contains("ergebnis") || t.contains("spiel"))

        if localOnly.contains(where: { t.contains($0) }) && !hasLive {
            return false
        }

        // Timeless encyclopedia — stay local unless also live-looking.
        let timeless =
            t.hasPrefix("was ist eine ") || t.hasPrefix("was ist ein ")
            || t.hasPrefix("wer war ") || t.hasPrefix("definiere ")
            || t.hasPrefix("erkläre ") || t.hasPrefix("erklaere ")
            || t.hasPrefix("wie funktioniert eine ") || t.hasPrefix("wie funktioniert ein ")
        if timeless && !hasLive {
            return false
        }

        // Short follow-ups after a live topic (Companion resolves context server-side).
        if isShortFollowUp(t) { return true }

        return hasLive
    }

    /// Resolve prior user asks for follow-up UI hints (Companion still does real context merge).
    static func likelyNeedsWeb(text: String, priorUserAsks: [String]) -> Bool {
        if likelyNeedsWeb(text) { return true }
        guard isShortFollowUp(text.lowercased()), !priorUserAsks.isEmpty else { return false }
        return priorUserAsks.suffix(3).contains { likelyNeedsWeb($0) }
    }

    private static func isShortFollowUp(_ t: String) -> Bool {
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count < 28 {
            let prefixes = ["und ", "auch ", "dabei ", "davon ", "dazu ", "wie steht", "wann ist", "wer hat", "was ist mit", "nächste", "naechste"]
            if prefixes.contains(where: { s.hasPrefix($0) }) { return true }
        }
        return false
    }

    static func resolveWire(
        policy: LiveKnowledgePolicy = .current,
        once: LiveKnowledgeOnceOverride?
    ) -> String {
        if let once {
            return once == .web ? "on" : "off"
        }
        return policy.wireValue
    }

    static func resolveSpeakWire(once: LiveKnowledgeOnceOverride? = nil) -> String {
        resolveWire(policy: SpeakLiveKnowledgePolicy.current, once: once)
    }
}

private enum RegexHelpers {
    static func containsWord(_ text: String, _ word: String) -> Bool {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}
