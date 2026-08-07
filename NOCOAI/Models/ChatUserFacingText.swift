import Foundation

/// Keeps system / Speak / mode prompts out of the visible chat transcript.
enum ChatUserFacingText {
    /// Prefer an explicit display string; otherwise strip wire prompts down to the real user ask.
    static func visibleUserText(wire: String, display: String? = nil) -> String {
        if let display {
            let d = display.trimmingCharacters(in: .whitespacesAndNewlines)
            if !d.isEmpty { return sanitize(d) }
        }
        return sanitize(wire)
    }

    static func sanitize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        // Prefer the last "Nutzer:" / "Frage:" payload inside a system wrapper.
        if let extracted = extractLabeledPayload(from: text) {
            return extracted
        }

        // Drop leading [NOCO …] instruction blocks.
        if text.hasPrefix("[") || text.uppercased().contains("[NOCO") {
            let lines = text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            let cleaned = lines.filter { line in
                let lower = line.lowercased()
                if line.hasPrefix("[") && line.contains("]") { return false }
                if lower.hasPrefix("noco speak") { return false }
                if lower.contains("gesprochene antwort") { return false }
                if lower.contains("antworte ausschließlich") { return false }
                if lower.contains("keine meta") { return false }
                if lower.contains("halte dich besonders kurz") { return false }
                if lower.contains("priorisiere qualität") { return false }
                if lower.contains("sei kreativ") { return false }
                if lower.contains("ton: professionell") { return false }
                if lower.contains("erkläre etwas ausführlicher") { return false }
                if lower.contains("du bist noco") { return false }
                if lower.contains("struktur:") { return false }
                if lower.contains("verbote:") { return false }
                if lower.hasPrefix("direkt,") || lower == "direkt" { return false }
                if lower.contains("1–4 sätze") || lower.contains("1-4 sätze") { return false }
                return true
            }
            if let last = cleaned.last, !looksLikeInstruction(last) {
                text = last
            } else if !cleaned.isEmpty {
                text = cleaned
                    .filter { !looksLikeInstruction($0) }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractLabeledPayload(from text: String) -> String? {
        let labels = [
            "Nutzerfrage:", "Nutzer:", "Auftrag:", "Frage:", "Thema:", "Briefing:",
            "User:", "Goal:", "Ziel:"
        ]
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        for label in labels {
            if let range = normalized.range(of: label, options: [.caseInsensitive, .backwards]) {
                let payload = String(normalized[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !payload.isEmpty, !looksLikeInstruction(payload) {
                    return payload
                }
            }
        }
        return nil
    }

    private static func looksLikeInstruction(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.hasPrefix("[") { return true }
        if lower.contains("gesprochene antwort") { return true }
        if lower.contains("auf deutsch") && lower.contains("antwort") { return true }
        if lower.contains("1–4 sätze") || lower.contains("1-4 sätze") { return true }
        if lower.contains("keine meta") { return true }
        return false
    }
}
