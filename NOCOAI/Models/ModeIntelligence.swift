import Foundation
import SwiftUI

/// Work-phase theater while NOCO is thinking / acting.
enum ModeWorkPhase: String, Equatable {
    case idle
    case understanding
    case analyzing
    case executing
    case done

    var title: String {
        switch self {
        case .idle: return "Bereit"
        case .understanding: return "Versteht Anfrage"
        case .analyzing: return "Denkt nach"
        case .executing: return "Erstellt Antwort"
        case .done: return "Fertig"
        }
    }

    var emoji: String {
        switch self {
        case .idle: return "✨"
        case .understanding: return "🧠"
        case .analyzing: return "✨"
        case .executing: return "⚙️"
        case .done: return "✅"
        }
    }

    var symbol: String {
        switch self {
        case .idle: return "sparkles"
        case .understanding: return "brain.head.profile"
        case .analyzing: return "sparkles"
        case .executing: return "gearshape.2.fill"
        case .done: return "checkmark.circle.fill"
        }
    }
}

/// Recommends modes, tracks recent/favorites — glue between chat, vision, and agent.
enum ModeIntelligence {
    private static let recentKey = "nocoai.modes.recent"
    private static let favoriteKey = "nocoai.modes.favorites"

    /// Depth-only recommendation for Auto (never Vision / Agent / specialty modes).
    /// Uses complexity signals — not just message length.
    static func recommendDepth(text: String) -> (mode: AIMode, reason: String)? {
        let t = text.lowercased()
        let len = text.count
        let lines = text.split(whereSeparator: \.isNewline).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count

        // Hard Flash shortcuts — skip when Live Knowledge is needed
        if !LiveKnowledgeRouting.likelyNeedsWeb(text) {
            if matches(t, #"^(was ist|wer ist|wann |wo |wie viel|übersetze|translate|danke|ok|okay|ja|nein)\b"#)
                && len < 80 {
                return (.flash, "Flash — einfache Faktenfrage")
            }
            if matches(t, #"^(kurz|schnell|tl;dr|eine zeile|ja oder nein)\b"#) {
                return (.flash, "Flash — kurze Antwort gewünscht")
            }
        }

        var score = 0
        if len > 220 { score += 2 }
        if len > 400 { score += 2 }
        if lines >= 4 { score += 2 }
        if lines >= 8 { score += 2 }

        if matches(
            t,
            "analysiere|vergleich|strategie|plane |planung|mehrere schritte|schritt für schritt|architektur|refactor|debug|algorithm|komplex|gründlich|abwägen|pro und contra|bewerte|entwirf|implementier|programmier|mathe|berechne|gleichung|beweis|warum funktioniert|wie baue ich|workflow|konzept"
        ) {
            score += 3
        }
        if matches(t, "code|swift|python|typescript|javascript|sql|bug|fehler") {
            score += 2
        }
        if matches(t, #"\b1[\).\]]|\b2[\).\]]|\b3[\).\]]"#) {
            score += 2
        }
        if matches(t, "und dann.*und dann|danach.*danach") {
            score += 2
        }

        if matches(t, "was ist eine |definiere kurz|übersetze|translate|wetter|uhrzeit|witz|hallo") {
            score -= 2
        }
        if len < 55 {
            score -= 1
        }

        if score >= 3 {
            return (.think, "Think — komplexere Aufgabe")
        }
        return (.flash, "Flash — schnelle Antwort")
    }

    /// Soft specialty hint (chips only) — never auto-activates Vision/Agent from Auto.
    static func recommend(
        text: String,
        hasImage: Bool = false,
        desktopProcess: String? = nil
    ) -> (mode: AIMode, reason: String)? {
        let t = text.lowercased()
        let proc = (desktopProcess ?? "").lowercased()

        // Images: suggest Agent or Speak camera — not a chat Vision mode switch
        if hasImage {
            return (.agent, "Agent kann Bilder und Tools kombinieren")
        }
        if matches(t, "kamera|was siehst|schau mal|erkenne das") {
            return nil // Vision gehört in Speak
        }
        if matches(t, "code|bug|fehler|swift|python|typescript|refactor|debug|kompil")
            || matches(proc, "code|devenv|cursor|xcode") {
            return (.think, "Think — Code braucht oft mehr Tiefe")
        }
        if matches(t, "erledige|plane|automat|workflow|installier|öffne|agent|mehrere schritte|computer control|webseite|website|app bauen|poster") {
            return (.agent, "Agent empfohlen — mehrstufige Aufgabe")
        }
        return recommendDepth(text: text)
    }

    /// After a reply: suggest the next intelligent area (cross-mode bridge).
    static func suggestNext(
        current: AIMode,
        userText: String,
        assistantText: String
    ) -> (mode: AIMode, reason: String)? {
        let blob = (userText + "\n" + assistantText).lowercased()
        if current == .vision {
            if matches(blob, "code|function|class |swift|python|fehler|bug") {
                return (.developer, "Developer als Nächstes — Code erkannt")
            }
            if matches(blob, "dokument|brief|text|schreiben|bewerbung|zusammenfass") {
                return (.writing, "Writing als Nächstes — Text aus dem Bild")
            }
            if matches(blob, "lern|erklär|begriff|definition") {
                return (.study, "Study als Nächstes — Wissen vertiefen")
            }
        }
        if current == .writing || current == .creative {
            if matches(blob, "code|html|css|react|implement|programm") {
                return (.developer, "Developer als Nächstes — Umsetzung in Code")
            }
            if matches(blob, "bild|visual|design|mockup") {
                return (.creative, "Creative — visuelle Ideen")
            }
        }
        if current == .developer {
            if matches(blob, "ui|design|layout|farbe|mockup") {
                return (.creative, "Creative — Design-Review")
            }
            if matches(blob, "erkläre|lernen|tutorial") {
                return (.study, "Study — Code erklären")
            }
        }
        if current == .study, matches(blob, "übung|quiz|zusammenfass") {
            return (.writing, "Writing — Lernzettel formulieren")
        }
        if matches(blob, "webseite|website|landing|app erstellen|mehrere schritte") {
            return (.agent, "Agent — Creative + Developer kombinieren")
        }
        return nil
    }

    /// Built-in workflows: ordered tool hints the Agent can follow (not chat mode switches).
    static func workflow(for goal: String) -> [AIMode]? {
        let g = goal.lowercased()
        if matches(g, "webseite|website|landing|homepage") {
            return [.creative, .developer]
        }
        if matches(g, "bewerbung|anschreiben") {
            return [.writing, .creative]
        }
        if matches(g, "lernplan|klausur|prüfung") {
            return [.study, .writing]
        }
        if matches(g, "poster|bild gener|bild erstellen|logo|visual") {
            return [.creative, .writing]
        }
        if matches(g, "bug|fehler|crash") {
            return [.developer]
        }
        return nil
    }

    static func recordUse(_ mode: AIMode) {
        var recent = loadList(recentKey)
        recent.removeAll { $0 == mode.rawValue }
        recent.insert(mode.rawValue, at: 0)
        saveList(Array(recent.prefix(8)), key: recentKey)
    }

    static func recentModes() -> [AIMode] {
        loadList(recentKey)
            .compactMap { raw -> AIMode? in
                let m = AIMode.from(raw)
                return AIMode.premiumCases.contains(m) ? m : nil
            }
    }

    static func favoriteModes() -> [AIMode] {
        loadList(favoriteKey).map { AIMode.from($0) }
    }

    static func toggleFavorite(_ mode: AIMode) {
        var fav = loadList(favoriteKey)
        if let idx = fav.firstIndex(of: mode.rawValue) {
            fav.remove(at: idx)
        } else {
            fav.insert(mode.rawValue, at: 0)
        }
        saveList(Array(fav.prefix(6)), key: favoriteKey)
    }

    static func isFavorite(_ mode: AIMode) -> Bool {
        loadList(favoriteKey).contains(mode.rawValue)
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func loadList(_ key: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    private static func saveList(_ list: [String], key: String) {
        UserDefaults.standard.set(list, forKey: key)
    }
}

extension AIMode {
    var preview: String {
        switch self {
        case .auto: return "NOCO wählt den besten Bereich und das passende Modell."
        case .agent: return "Plant, nutzt Tools, prüft Ergebnisse — wie ein digitaler Mitarbeiter."
        case .vision: return "Bilder, Kamera und Bildschirm verstehen."
        case .developer: return "Code analysieren, Fehler finden, Projekte verbessern."
        case .writing: return "Schreiben, kürzen, Ton ändern, zusammenfassen."
        case .study: return "Erklären, Lernpläne, Zusammenfassungen, Quiz."
        case .creative: return "Ideen, Konzepte, Bildimpulse, Designs."
        case .image: return "Idee beschreiben — NOCO macht daraus ein Bild im Chat."
        case .flash: return "Sehr schnelle, kurze Antworten."
        case .knowledge: return "Fakten ohne langen Chat-Kontext."
        case .think: return "Tiefes Nachdenken und Reasoning."
        }
    }

    var accentColor: Color {
        switch self {
        case .auto: return Color(red: 0.55, green: 0.45, blue: 1.0)
        case .agent: return Color(red: 0.35, green: 0.78, blue: 0.72)
        case .vision: return Color(red: 0.45, green: 0.72, blue: 1.0)
        case .developer: return Color(red: 0.78, green: 0.62, blue: 0.98)
        case .writing: return Color(red: 0.98, green: 0.72, blue: 0.38)
        case .study: return Color(red: 0.35, green: 0.82, blue: 0.62)
        case .creative: return Color(red: 1.0, green: 0.45, blue: 0.72)
        case .image: return Color(red: 0.95, green: 0.55, blue: 0.35)
        case .flash: return Color(red: 1.0, green: 0.78, blue: 0.28)
        case .knowledge: return Color(red: 0.4, green: 0.7, blue: 0.95)
        case .think: return Color(red: 0.55, green: 0.5, blue: 0.95)
        }
    }

    /// Companion chat wire value (`nil` = auto-select on server).
    var wireModeValue: String? {
        switch self {
        case .auto, .image: return nil
        case .flash: return "flash"
        case .knowledge: return "knowledge"
        case .think, .agent: return "think"
        case .vision: return "vision"
        case .developer: return "developer"
        case .writing: return "writing"
        case .study: return "study"
        case .creative: return "creative"
        }
    }

    var modelHint: String {
        switch self {
        case .auto: return "Auto-Modell"
        case .agent: return "Reasoning-Modell"
        case .vision: return "Vision-Modell"
        case .developer: return "Coding-Modell"
        case .writing: return "Schreib-Modell"
        case .study: return "Wissens-Modell"
        case .creative: return "Kreativ-Modell"
        case .image: return "Bild"
        case .flash: return "Schnell-Modell"
        case .knowledge: return "Fakten-Modell"
        case .think: return "Denk-Modell"
        }
    }

    var agentKindBridge: AgentKind {
        switch self {
        case .developer: return .coding
        case .study: return .study
        case .creative: return .creative
        default: return .general
        }
    }

    func specialtyPrompt(for userText: String) -> String? {
        switch self {
        case .developer:
            return """
            [NOCO DEVELOPER]
            Du bist NOCO im Developer-Bereich. Analysiere Code, finde Fehler, erkläre klar auf Deutsch.
            Struktur: Kurzfazit → Analyse → konkrete Fixes → nächste Schritte.
            Nutzer:
            \(userText)
            """
        case .writing:
            return """
            [NOCO WRITING]
            Du bist NOCO Writing. Schreibe oder verbessere Texte auf Deutsch — klar, stilvoll, ohne Floskeln.
            Auftrag:
            \(userText)
            """
        case .study:
            return """
            [NOCO STUDY]
            Du bist NOCO Study. Erkläre verständlich, baue Lernpläne, fasse zusammen, optional kurze Quizfragen.
            Struktur: Kernidee → Erklärung → Merksätze → Übung.
            Thema:
            \(userText)
            """
        case .creative:
            return """
            [NOCO CREATIVE]
            Du bist NOCO Creative. Liefere originelle Ideen, Konzepte und Bild-/Design-Impulse auf Deutsch.
            Sei mutig, aber umsetzbar.
            Briefing:
            \(userText)
            """
        case .vision:
            return """
            [NOCO VISION — BILDANALYSE AKTIV]
            Du bist NOCO Vision und KANNST Bilder sehen, beschreiben und erklären.
            Verbote: Sage niemals, dass du keine Bilder anzeigen, sehen oder beschreiben kannst.
            Wenn in dieser Nachricht kein Bild steckt: bitte höflich um ein Foto (+ Kamera) und gib \
            trotzdem die beste mögliche Text-Hilfe zur Frage.
            Frage:
            \(userText)
            """
        default:
            return nil
        }
    }
}
