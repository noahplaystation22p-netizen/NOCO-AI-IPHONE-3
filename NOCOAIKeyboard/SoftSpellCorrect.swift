import UIKit

/// Lightweight German spell-check on space — no suggestion bar, no AI, not English.
enum SoftSpellCorrect {
    /// Returns a replacement only for clear German typos (conservative).
    static func suggestion(for word: String) -> String? {
        let raw = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count >= 4, raw.count <= 28 else { return nil }
        // Skip URLs / handles / codes / mixed junk
        if raw.contains("@") || raw.contains(".") || raw.contains("/") { return nil }
        if raw.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) }) { return nil }
        // Never autocorrect short function words / particles
        let low = raw.lowercased()
        if germanStopWords.contains(low) { return nil }

        let checker = UITextChecker()
        // German QWERTZ keyboard → German dictionary only (never English fallback).
        let langs = ["de_DE", "de"]
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
            // Word is fine in German — leave it.
            guard misspelled.location != NSNotFound else { return nil }

            guard let guesses = checker.guesses(forWordRange: misspelled, in: raw, language: lang),
                  let best = guesses.first else { continue }

            let a = raw.lowercased()
            let b = best.lowercased()
            guard a != b else { return nil }

            // Less aggressive: only very close edits.
            let dist = editDistance(a, b)
            let maxDist = a.count <= 5 ? 1 : 2
            guard dist <= maxDist else { continue }

            // Reject English-looking swaps for German typing (e.g. „ist“→„is“, „und“→„and“).
            if looksLikeEnglishReplacement(original: a, replacement: b) { continue }

            // Prefer same length ±1 for short words.
            if a.count <= 6, abs(a.count - b.count) > 1 { continue }

            return matchCase(of: raw, to: best)
        }
        return nil
    }

    private static let germanStopWords: Set<String> = [
        "der", "die", "das", "den", "dem", "des", "ein", "eine", "einer", "einem", "einen",
        "und", "oder", "aber", "mit", "von", "zu", "im", "in", "am", "an", "auf", "für", "fur",
        "ist", "sind", "war", "bin", "bist", "hat", "hab", "habe", "wir", "ihr", "sie", "ich",
        "du", "er", "es", "man", "nur", "noch", "auch", "nicht", "nein", "ja", "ok", "okay"
    ]

    /// Heuristic: English dictionary corrections that steal German words.
    private static func looksLikeEnglishReplacement(original: String, replacement: String) -> Bool {
        // If original has German letters, never replace with ASCII-only English form that drops them.
        let germanChars = CharacterSet(charactersIn: "äöüßÄÖÜ")
        let origHasDE = original.unicodeScalars.contains(where: { germanChars.contains($0) })
        let replHasDE = replacement.unicodeScalars.contains(where: { germanChars.contains($0) })
        if origHasDE && !replHasDE { return true }

        // Known false friends / aggressive EN swaps
        let bannedPairs: Set<String> = [
            "ist>is", "und>and", "oder>or", "mit>with", "für>for", "fur>for",
            "nicht>not", "auch>also", "noch>still", "dann>then", "wenn>when",
            "wie>how", "was>what", "wer>who", "wo>where", "hier>here", "dort>there",
            "gut>good", "sehr>very", "mein>my", "dein>your", "kein>no", "keine>no",
            "tempo>tempo", // leave; but block tempo→time etc via other checks
            "ai>ai" // no-op
        ]
        if bannedPairs.contains("\(original)>\(replacement)") { return true }

        // Replacement is a common English function word while original is not the same.
        let englishFunction: Set<String> = [
            "is", "are", "was", "were", "the", "and", "or", "with", "for", "not",
            "what", "how", "when", "where", "who", "why", "this", "that", "have", "has",
            "been", "will", "would", "could", "should", "from", "into", "about"
        ]
        if englishFunction.contains(replacement), !englishFunction.contains(original) {
            return true
        }
        return false
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
