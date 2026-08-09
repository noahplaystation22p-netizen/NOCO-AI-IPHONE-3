import Foundation
import UIKit

/// Session-friendly clipboard history for the keyboard extension.
/// iOS does not expose a full system clipboard history to custom keyboards —
/// with Full Access we can read the *current* pasteboard string once, and we
/// keep a private NOCO list of texts the keyboard itself handled.
enum KeyboardClipboardStore {
    private static let appGroupId = "group.de.noco.nocoai"
    private static let key = "nocoai.keyboard.clipboard.history.v1"
    private static let maxItems = 20
    private static let maxItemChars = 2_000

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupId) ?? .standard
    }

    static func items() -> [String] {
        (defaults.stringArray(forKey: key) ?? []).filter { !$0.isEmpty }
    }

    /// Prefers current system pasteboard (Full Access) on top, then NOCO history.
    static func displayItems(hasFullAccess: Bool) -> [(text: String, isSystem: Bool)] {
        var result: [(String, Bool)] = []
        var seen = Set<String>()

        if hasFullAccess, let clip = sanitized(UIPasteboard.general.string), !clip.isEmpty {
            result.append((clip, true))
            seen.insert(clip)
        }

        for item in items() {
            guard !seen.contains(item) else { continue }
            result.append((item, false))
            seen.insert(item)
            if result.count >= maxItems { break }
        }
        return result
    }

    static func remember(_ raw: String) {
        guard let text = sanitized(raw), !text.isEmpty else { return }
        // Never persist credential bridge payloads.
        if text.hasPrefix("nocoai-cred:") { return }
        var list = items().filter { $0 != text }
        list.insert(text, at: 0)
        if list.count > maxItems {
            list = Array(list.prefix(maxItems))
        }
        defaults.set(list, forKey: key)
    }

    static func clear() {
        defaults.removeObject(forKey: key)
    }

    private static func sanitized(_ raw: String?) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if text.count > maxItemChars {
            text = String(text.prefix(maxItemChars))
        }
        return text
    }
}
