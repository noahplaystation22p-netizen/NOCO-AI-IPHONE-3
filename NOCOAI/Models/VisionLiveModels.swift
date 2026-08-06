import Foundation
import SwiftUI

enum VisionLiveIntent: String, CaseIterable, Identifiable {
    case understand
    case help
    case learn
    case document
    case product
    case repair

    var id: String { rawValue }

    var title: String {
        switch self {
        case .understand: return "Verstehen"
        case .help: return "Helfen"
        case .learn: return "Lernen"
        case .document: return "Dokument"
        case .product: return "Produkt"
        case .repair: return "Reparatur"
        }
    }

    var subtitle: String {
        switch self {
        case .understand: return "Was sehe ich — und warum?"
        case .help: return "Nächste sinnvolle Aktion"
        case .learn: return "Erklären & üben"
        case .document: return "Zusammenfassen & Punkte"
        case .product: return "Erkennen & einordnen"
        case .repair: return "Fehler & Lösung"
        }
    }

    var systemImage: String {
        switch self {
        case .understand: return "eye.fill"
        case .help: return "hand.raised.fill"
        case .learn: return "book.fill"
        case .document: return "doc.text.fill"
        case .product: return "tag.fill"
        case .repair: return "wrench.and.screwdriver.fill"
        }
    }

    var accent: Color {
        switch self {
        case .understand: return Color(red: 0.42, green: 0.68, blue: 1.0)
        case .help: return Color(red: 0.35, green: 0.82, blue: 0.62)
        case .learn: return Color(red: 0.78, green: 0.62, blue: 0.98)
        case .document: return Color(red: 0.98, green: 0.72, blue: 0.38)
        case .product: return Color(red: 1.0, green: 0.55, blue: 0.45)
        case .repair: return Color(red: 0.95, green: 0.45, blue: 0.55)
        }
    }

    var systemDirective: String {
        switch self {
        case .understand:
            return """
            Du bist NOCO Vision Live — die Augen von NOCO AI. Du siehst die Kamera-Umgebung des Nutzers. \
            Beschreibe nicht nur Objekte: verstehe die Situation, Absicht und was als Nächstes hilfreich wäre. \
            Antworte auf Deutsch, warm und klar, als säßest du neben dem Nutzer.
            """
        case .help:
            return """
            Du bist NOCO Vision Live im Hilfemodus. Erkenne, was der Nutzer erreichen will, und gib konkrete nächste Schritte. \
            Biete aktiv Hilfe an (z. B. Einrichtung, Bedienung, Sicherheit).
            """
        case .learn:
            return """
            Du bist NOCO Vision Live als Lernassistent. Erkenne Aufgaben, Texte, Diagramme. \
            Erkläre verständlich, gib Hinweise bevor die volle Lösung — außer der Nutzer will die Lösung direkt.
            """
        case .document:
            return """
            Du bist NOCO Vision Live für Dokumente. Lies sichtbaren Text (OCR), fasse Kernpunkte zusammen, \
            nenne Fristen/Adressen/Beträge wenn erkennbar, schlage sinnvolle Folgeaktionen vor.
            """
        case .product:
            return """
            Du bist NOCO Vision Live für Produkte/Geräte. Erkenne Typ, Marke falls möglich, typische Nutzung \
            und biete Einrichtungshilfe oder Vergleichsaspekte an — ohne erfundenes Wissen.
            """
        case .repair:
            return """
            Du bist NOCO Vision Live als Reparatur-/Fehlerassistent. Erkenne Fehlermeldungen, Zustände, Gefahren. \
            Gib sichere, schrittweise Tipps. Bei Gefahr (Strom, Gas, Hitze) klar warnen.
            """
        }
    }

    var defaultPrompt: String {
        switch self {
        case .understand: return "Was sehe ich hier — und was wäre jetzt hilfreich?"
        case .help: return "Was soll ich jetzt tun? Gib konkrete Schritte."
        case .learn: return "Erkläre mir, was hier zu sehen ist, und hilf mir zu lernen."
        case .document: return "Fasse dieses Dokument zusammen und nenne die wichtigsten Punkte."
        case .product: return "Was ist das für ein Produkt/Gerät, und wie kann ich es nutzen?"
        case .repair: return "Erkenne das Problem und schlage sichere Lösungen vor."
        }
    }
}

struct VisionLiveTurn: Identifiable, Equatable {
    let id: UUID
    let role: Role
    let text: String
    let createdAt: Date

    enum Role { case user, assistant, system }

    init(id: UUID = UUID(), role: Role, text: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

struct VisionLiveSuggestion: Identifiable, Equatable {
    let id: String
    let title: String
    let prompt: String
    let systemImage: String

    static func from(ocr: String, intent: VisionLiveIntent) -> [VisionLiveSuggestion] {
        var list: [VisionLiveSuggestion] = [
            .init(id: "see", title: "Was sehe ich?", prompt: "Was sehe ich hier, und was ist wichtig?", systemImage: "eye"),
            .init(id: "next", title: "Was jetzt tun?", prompt: "Was soll ich jetzt machen? Gib klare nächste Schritte.", systemImage: "arrow.right.circle")
        ]
        let lower = ocr.lowercased()
        if lower.count > 80 {
            list.append(.init(id: "sum", title: "Text zusammenfassen", prompt: "Lies den sichtbaren Text und fasse die Kernpunkte zusammen.", systemImage: "text.alignleft"))
        }
        if lower.contains("error") || lower.contains("fehler") || lower.contains("exception") {
            list.append(.init(id: "err", title: "Fehler erklären", prompt: "Erkläre den sichtbaren Fehler und wie ich ihn behebe.", systemImage: "exclamationmark.triangle"))
        }
        if intent == .learn || lower.contains("aufgabe") || lower.contains("gleichung") || lower.contains("=") {
            list.append(.init(id: "learn", title: "Aufgabe erklären", prompt: "Ich erkenne eine Lernaufgabe — erkläre sie verständlich Schritt für Schritt.", systemImage: "book"))
        }
        return Array(list.prefix(4))
    }
}

enum VisionLiveFuture: String, CaseIterable {
    case ar, smartGlasses, liveTranslation, gaming, shopping, repair, study

    var title: String {
        switch self {
        case .ar: return "AR"
        case .smartGlasses: return "Smart Glasses"
        case .liveTranslation: return "Live-Übersetzung"
        case .gaming: return "Gaming"
        case .shopping: return "Shopping"
        case .repair: return "Reparatur"
        case .study: return "Lernen"
        }
    }
}
