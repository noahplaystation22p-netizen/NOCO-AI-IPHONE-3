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
        case .understanding: return "Verstehen"
        case .analyzing: return "Analysieren"
        case .executing: return "Ausführen"
        case .done: return "Fertig"
        }
    }

    var symbol: String {
        switch self {
        case .idle: return "sparkles"
        case .understanding: return "brain.head.profile"
        case .analyzing: return "magnifyingglass"
        case .executing: return "gearshape.2.fill"
        case .done: return "checkmark.circle.fill"
        }
    }
}

/// Recommends modes, tracks recent/favorites — glue between chat, vision, and agent.
enum ModeIntelligence {
    private static let recentKey = "nocoai.modes.recent"
    private static let favoriteKey = "nocoai.modes.favorites"

    static func recommend(
        text: String,
        hasImage: Bool = false,
        desktopProcess: String? = nil
    ) -> (mode: AIMode, reason: String)? {
        let t = text.lowercased()
        let proc = (desktopProcess ?? "").lowercased()

        if hasImage || matches(t, "bild|foto|screenshot|kamera|erkenne|was siehst|ocr|scanne") {
            return (.vision, "Vision empfohlen — Bild oder Bildschirm")
        }
        if matches(t, "code|bug|fehler|swift|python|typescript|refactor|debug|kompil")
            || matches(proc, "code|devenv|cursor|xcode") {
            return (.developer, "Developer empfohlen — Programmierung")
        }
        if matches(t, "lern|erklär|klausur|schule|studium|quiz") {
            return (.study, "Study empfohlen — Lernen")
        }
        if matches(t, "schreib|umformulier|kürz|länger|bewerbung|e-mail|email|text verbessern")
            || matches(proc, "winword|word") {
            return (.writing, "Writing empfohlen — Textarbeit")
        }
        if matches(t, "idee|konzept|kreativ|design|slogan|brain.?storm|bildidee|logo") {
            return (.creative, "Creative empfohlen — Ideen")
        }
        if matches(t, "erledige|plane|automat|workflow|installier|öffne|agent|mehrere schritte|computer control|webseite|website|app bauen") {
            return (.agent, "Agent empfohlen — mehrstufige Aufgabe")
        }
        return nil
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

    /// Built-in workflows: ordered mode chains the Agent can follow.
    static func workflow(for goal: String) -> [AIMode]? {
        let g = goal.lowercased()
        if matches(g, "webseite|website|landing|homepage") {
            return [.creative, .developer, .vision]
        }
        if matches(g, "bewerbung|anschreiben") {
            return [.writing, .creative, .writing]
        }
        if matches(g, "lernplan|klausur|prüfung") {
            return [.study, .writing, .study]
        }
        if matches(g, "bug|fehler|crash") {
            return [.developer, .vision, .developer]
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
        case .flash: return Color(red: 1.0, green: 0.78, blue: 0.28)
        case .knowledge: return Color(red: 0.4, green: 0.7, blue: 0.95)
        case .think: return Color(red: 0.55, green: 0.5, blue: 0.95)
        }
    }

    /// Companion chat wire value (`nil` = auto-select on server).
    var wireModeValue: String? {
        switch self {
        case .auto: return nil
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
            [NOCO VISION]
            Du bist NOCO Vision. Beschreibe und interpretiere visuelle Inhalte. Wenn kein Bild angehängt ist, \
            sage klar, dass ein Foto/Screenshot hilft, und gib trotzdem die beste Text-Hilfe.
            Frage:
            \(userText)
            """
        default:
            return nil
        }
    }
}
