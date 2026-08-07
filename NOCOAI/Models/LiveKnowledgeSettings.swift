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
    static func likelyNeedsWeb(_ text: String) -> Bool {
        let t = text.lowercased()
        let needles = [
            "aktuell", "nachrichten", "news", "wetter", "temperatur",
            "vorhersage", "preis", "kostet", "spielstand", "ergebnis", "gewonnen", "bundesliga",
            "champions league", "bitcoin", "aktie", "kurs", "release", "schau nach", "recherchier",
            "suche im internet", "google", "im web", "online nach", "live", "wer hat gewonnen",
            "wie viel kostet", "neueste", "schlagzeile", "was gibt es neues", "was ist passiert",
            "zug", "bahn", "fahrplan", "abfahrt", "ankunft", "verkehr", "stau", "wahl",
            "wer spielt", "spielt heute", "heutige spiele", "spielplan", "formel 1", "f1 ",
            "iphone neu", "neuerscheinung", "ticker", "apple news", "dieser woche", "dieses jahr"
        ]
        // Writing / planning without live intent stays local (avoid "morgen" alone firing web).
        let localOnly = [
            "schreib", "gedicht", "geschichte", "übersetze", "ubersetze", "refaktor",
            "erkläre mir einfach", "erklare mir einfach", "formulier", "mach mir einen plan"
        ]
        if localOnly.contains(where: { t.contains($0) }) {
            let stillLive = needles.contains(where: { t.contains($0) })
                || t.contains("wetter") || t.contains("nachrichten") || t.contains("preis")
            if !stillLive { return false }
        }
        return needles.contains(where: { t.contains($0) })
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
