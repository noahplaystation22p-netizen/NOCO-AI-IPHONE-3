import UIKit

/// Lightweight system spell-check on space — fixes obvious typos without a suggestion bar or AI.
enum SoftSpellCorrect {
    /// Returns a replacement only when UITextChecker is confident (single clear guess).
    static func suggestion(for word: String) -> String? {
        let raw = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count >= 3, raw.count <= 32 else { return nil }
        // Skip URLs / handles / codes
        if raw.contains("@") || raw.contains(".") || raw.contains("/") { return nil }
        if raw.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) }) { return nil }

        let checker = UITextChecker()
        let langs = preferredLanguages()
        let ns = raw as NSString
        let full = NSRange(location: 0, length: ns.length)

        for lang in langs {
            let misspelled = checker.rangeOfMisspelledWord(
                in: raw,
                range: full,
                startingAt: 0,
                wrap: false,
                language: lang
            )
            guard misspelled.location != NSNotFound else { continue }
            guard let guesses = checker.guesses(forWordRange: misspelled, in: raw, language: lang),
                  let best = guesses.first else { continue }
            // Prefer close edits (Baun→Baum); avoid wild rewrites.
            guard editDistance(raw.lowercased(), best.lowercased()) <= 2 else { continue }
            return matchCase(of: raw, to: best)
        }
        return nil
    }

    private static func preferredLanguages() -> [String] {
        var langs = ["de_DE", "de", "en_US", "en"]
        for code in Locale.preferredLanguages {
            if !langs.contains(code) { langs.insert(code, at: 0) }
        }
        return langs
    }

    private static func matchCase(of original: String, to replacement: String) -> String {
        if original == original.uppercased(), original.count > 1 {
            return replacement.uppercased()
        }
        if let f = original.first, f.isUppercase {
            return replacement.prefix(1).uppercased() + replacement.dropFirst()
        }
        return replacement
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count
        if m == 0 { return n }
        if n == 0 { return m }
        var prev = Array(0...n)
        var cur = Array(repeating: 0, count: n + 1)
        for i in 1...m {
            cur[0] = i
            for j in 1...n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            prev = cur
        }
        return prev[n]
    }
}
