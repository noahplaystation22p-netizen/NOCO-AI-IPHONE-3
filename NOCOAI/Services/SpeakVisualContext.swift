import Foundation
import UIKit

/// Explicit Speak visual source — never ambiguous between screen and camera.
enum VisualMode: String, Equatable {
    case none
    case screen
    case camera

    var logName: String {
        switch self {
        case .none: return "none"
        case .screen: return "screen"
        case .camera: return "camera"
        }
    }

    var islandLabel: String {
        switch self {
        case .none: return "NOCO Voice"
        case .screen: return "NOCO Voice · Screen View"
        case .camera: return "NOCO Voice · Live View"
        }
    }
}

enum VisualSource: String, Equatable {
    case none
    case screen
    case camera
}

/// Internal visual memory for Speak follow-ups — not written as a giant chat turn.
struct VisualContext: Equatable {
    var source: VisualSource
    var capturedAt: Date
    var summary: String
    var relevantText: String
    /// Compact OCR / on-screen text when available.
    var ocrSnippet: String
    var generation: UInt64

    var age: TimeInterval { Date().timeIntervalSince(capturedAt) }

    var isFresh: Bool { age < 90 }

    var briefing: String {
        var parts: [String] = []
        parts.append("Quelle: \(source == .screen ? "Bildschirm" : "Kamera")")
        parts.append("Erfasst vor \(Int(age))s")
        if !summary.isEmpty { parts.append("Zusammenfassung:\n\(summary)") }
        if !relevantText.isEmpty { parts.append("Relevant:\n\(relevantText)") }
        if !ocrSnippet.isEmpty { parts.append("Textauszug:\n\(ocrSnippet)") }
        return parts.joined(separator: "\n\n")
    }
}

enum VisualRefreshReason: String {
    case none
    case noContext
    case stale
    case explicitRefresh
    case sourceMismatch
    case followUpNeedsDetail
}

enum VisualLog {
    static func event(_ name: String, _ detail: String = "") {
        VoiceDebugLog.event(name, detail)
    }
}
