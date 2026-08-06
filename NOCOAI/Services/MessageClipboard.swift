import Foundation
import UIKit
import UniformTypeIdentifiers

enum MessageClipboard {
    /// Strip markdown links, bare media URLs and UUID junk — paste as real readable text.
    static func plainText(from raw: String) -> String {
        var s = raw

        // [label](url) → label
        s = s.replacingOccurrences(
            of: #"\[([^\]]+)\]\(([^)]+)\)"#,
            with: "$1",
            options: .regularExpression
        )
        // Bare http(s) / nocoai / media paths on their own
        s = s.replacingOccurrences(
            of: #"(?m)^\s*(?:https?://|nocoai://|/api/v1/media/)[^\s]+\s*$"#,
            with: "",
            options: .regularExpression
        )
        // Inline media / api paths → drop
        s = s.replacingOccurrences(
            of: #"(?:https?://[^\s]+|/api/v1/media/[^\s]+|nocoai://[^\s]+)"#,
            with: "",
            options: .regularExpression
        )
        // Standalone UUID / long hex ids
        s = s.replacingOccurrences(
            of: #"(?m)^\s*[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\s*$"#,
            with: "",
            options: .regularExpression
        )
        s = s.replacingOccurrences(
            of: #"(?m)^\s*[0-9a-fA-F]{16,}\s*$"#,
            with: "",
            options: .regularExpression
        )
        // Collapse leftover whitespace
        s = s.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Put only plain UTF-8 text on the pasteboard (no URL / rich extras).
    static func copy(_ raw: String) {
        let plain = plainText(from: raw)
        guard !plain.isEmpty else { return }
        let pb = UIPasteboard.general
        pb.items = []
        if let data = plain.data(using: .utf8) {
            pb.setItems(
                [[UTType.utf8PlainText.identifier: data]],
                options: [:]
            )
        }
        // Ensure .string is set for older paste targets
        pb.string = plain
    }
}
