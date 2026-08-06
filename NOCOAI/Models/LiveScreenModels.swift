import Foundation
import SwiftUI

/// Intelligent assist modes for NOCO Live Screen.
enum LiveScreenMode: String, CaseIterable, Identifiable, Codable {
    case explain
    case help
    case analyze
    case assist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explain: return "Erklären"
        case .help: return "Helfen"
        case .analyze: return "Analysieren"
        case .assist: return "Assistent"
        }
    }

    var subtitle: String {
        switch self {
        case .explain: return "Was passiert gerade?"
        case .help: return "Konkrete nächste Schritte"
        case .analyze: return "Inhalt detailliert prüfen"
        case .assist: return "Sinnvolle Aktionen vorschlagen"
        }
    }

    var systemImage: String {
        switch self {
        case .explain: return "text.bubble.fill"
        case .help: return "hand.raised.fill"
        case .analyze: return "magnifyingglass.circle.fill"
        case .assist: return "sparkles"
        }
    }

    var accent: Color {
        switch self {
        case .explain: return Color(red: 0.42, green: 0.68, blue: 1.0)
        case .help: return Color(red: 0.35, green: 0.82, blue: 0.62)
        case .analyze: return Color(red: 0.78, green: 0.62, blue: 0.98)
        case .assist: return Color(red: 0.98, green: 0.72, blue: 0.38)
        }
    }

    /// Mode-specific instruction prepended to the vision request.
    var systemDirective: String {
        switch self {
        case .explain:
            return """
            Du bist NOCO Live Screen. Erkläre klar auf Deutsch, was auf dem Bildschirm sichtbar ist \
            und was der Nutzer gerade macht. Kontext verstehen, nicht nur auflisten. Kurz und hilfreich.
            """
        case .help:
            return """
            Du bist NOCO Live Screen im Hilfemodus. Erkenne die Situation und gib konkrete nächste Schritte \
            (nummeriert, kurz). Markiere mental wichtige Buttons/Felder und beschreibe wo der Nutzer tippen soll.
            """
        case .analyze:
            return """
            Du bist NOCO Live Screen im Analysemodus. Untersuche Texte, Fehlermeldungen, UI-Elemente und \
            Dokumentinhalte detailliert. Nenne Ursachen und relevante Details auf Deutsch.
            """
        case .assist:
            return """
            Du bist NOCO Live Screen als proaktiver Assistent. Schlage 2–4 sinnvolle Aktionen vor, \
            die dem Nutzer jetzt am meisten helfen (z. B. zusammenfassen, Fehler beheben, Einstellungen ändern). \
            Kurz, actionable, auf Deutsch.
            """
        }
    }

    var defaultUserPrompt: String {
        switch self {
        case .explain: return "Erkläre mir, was auf dem Bildschirm passiert."
        case .help: return "Wie komme ich hier weiter? Gib konkrete Schritte."
        case .analyze: return "Analysiere den Bildschirm detailliert."
        case .assist: return "Was wäre jetzt am sinnvollsten? Schlage Aktionen vor."
        }
    }
}

enum LiveScreenPhase: String, Equatable {
    case idle
    case recognizing
    case understanding
    case answering
    case done

    var title: String {
        switch self {
        case .idle: return "Bereit"
        case .recognizing: return "Erkennen"
        case .understanding: return "Verstehen"
        case .answering: return "Antwort"
        case .done: return "Fertig"
        }
    }

    var color: Color {
        switch self {
        case .idle: return Color(red: 0.55, green: 0.62, blue: 0.75)
        case .recognizing: return Color(red: 0.35, green: 0.62, blue: 1.0) // blue
        case .understanding: return Color(red: 0.72, green: 0.48, blue: 1.0) // violet
        case .answering: return Color(red: 0.95, green: 0.55, blue: 0.75)
        case .done: return Color(red: 0.28, green: 0.85, blue: 0.58) // green
        }
    }
}

enum LiveScreenQuality: String, CaseIterable, Identifiable, Codable {
    case auto
    case fast
    case accurate
    case creative
    case developer
    case offline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .fast: return "Schnell"
        case .accurate: return "Genau"
        case .creative: return "Kreativ"
        case .developer: return "Entwickler"
        case .offline: return "Offline"
        }
    }
}

struct LiveScreenSuggestedAction: Identifiable, Equatable {
    let id: String
    let title: String
    let prompt: String
    let systemImage: String

    static func from(ocr: String, mode: LiveScreenMode) -> [LiveScreenSuggestedAction] {
        var list: [LiveScreenSuggestedAction] = []
        let lower = ocr.lowercased()
        if lower.contains("error") || lower.contains("fehler") || lower.contains("exception") || lower.contains("failed") {
            list.append(.init(id: "err", title: "Fehlermeldung analysieren", prompt: "Analysiere die Fehlermeldung und schlage konkrete Lösungen vor.", systemImage: "exclamationmark.triangle.fill"))
        }
        if ocr.count > 120 {
            list.append(.init(id: "sum", title: "Text zusammenfassen", prompt: "Fasse den sichtbaren Text kurz und klar zusammen.", systemImage: "text.alignleft"))
        }
        list.append(.init(id: "steps", title: "Schritt für Schritt", prompt: "Erkläre Schritt für Schritt, was ich als Nächstes tun soll.", systemImage: "list.number"))
        list.append(.init(id: "reply", title: "Antwort erstellen", prompt: "Formuliere eine passende Antwort oder Nachricht basierend auf dem Bildschirm.", systemImage: "bubble.left.and.bubble.right.fill"))
        if mode == .assist {
            list.append(.init(id: "act", title: "Aktionen vorschlagen", prompt: "Schlage 3 sinnvolle nächste Aktionen vor.", systemImage: "sparkles"))
        }
        return Array(list.prefix(4))
    }
}

/// Extensible capture kinds — Broadcast / Camera / AR can plug in later.
enum LiveScreenCaptureKind: String, Codable {
    case photoLibrary
    case clipboard
    case inAppReplay
    case cameraLiveVision
    case broadcastExtension
    case documentScan
}

struct LiveScreenTurn: Identifiable, Equatable {
    let id: UUID
    let role: Role
    let text: String
    let createdAt: Date
    let thumbnailJPEG: Data?

    enum Role: String {
        case user
        case assistant
        case system
    }

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        createdAt: Date = Date(),
        thumbnailJPEG: Data? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.thumbnailJPEG = thumbnailJPEG
    }
}

struct LiveScreenFrame: Equatable {
    let jpegData: Data
    let ocrText: String
    let capturedAt: Date
    let source: LiveScreenCaptureKind
    let width: Int
    let height: Int
}

/// Future feature hooks — architecture placeholders, not UI spam.
enum LiveScreenFutureCapability: String, CaseIterable {
    case cameraLiveVision
    case arAssist
    case documentAnalysis
    case smartHomeHelp
    case codingAssist
    case gamingAssist
    case realtimeTranslation

    var title: String {
        switch self {
        case .cameraLiveVision: return "Kamera Live Vision"
        case .arAssist: return "AR-Unterstützung"
        case .documentAnalysis: return "Dokumentanalyse"
        case .smartHomeHelp: return "Smart Home Hilfe"
        case .codingAssist: return "Programmierhilfe"
        case .gamingAssist: return "Gaming-Assistent"
        case .realtimeTranslation: return "Echtzeit-Übersetzung"
        }
    }
}
