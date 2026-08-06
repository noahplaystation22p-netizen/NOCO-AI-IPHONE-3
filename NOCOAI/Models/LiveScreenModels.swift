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
