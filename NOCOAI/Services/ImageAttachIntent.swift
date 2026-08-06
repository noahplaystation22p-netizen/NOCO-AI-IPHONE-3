import Foundation

/// Decides whether an uploaded image should be described (vision) or edited (SD img2img).
enum ImageAttachIntent {
    case analyze
    case edit

    static func resolve(caption: String?) -> ImageAttachIntent {
        let t = (caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return .analyze }

        let lower = t.lowercased()

        if lower.range(of: #"^(was|wer|wo|warum|wieso|beschreib|analy|erkenne|sieh|schau|what's|what is|describe)"#, options: .regularExpression) != nil
            || lower.contains("im bild")
            || lower.contains("auf dem bild")
            || lower.contains("auf dem foto")
            || lower.contains("was siehst")
            || lower.contains("was ist das") {
            return .analyze
        }

        if lower.range(of: #"^(mach(?:e)?\s+mir\s+(?:ein\s+)?(?:bild|foto))"#, options: .regularExpression) != nil {
            return .analyze
        }

        let editHints = [
            "entferne", "remove", "lösch", "erase", "radier",
            "änder", "change", "mach ", "make ", "füg", "add ",
            "haar", "himmel", "sky", "hintergrund", "background",
            "baum", "person", "objekt", "rot", "blau", "grün",
            "größer", "kleiner", "heller", "dunkler", "mehr ", "weniger ",
            "verbesser", "improve", "bearbeit", "edit", "ersetze", "replace"
        ]
        if editHints.contains(where: { lower.contains($0) }) {
            return .edit
        }

        if lower.range(of: #"^(mehr|weniger|stärker|schwächer)\s+\w+"#, options: .regularExpression) != nil {
            return .edit
        }

        return .analyze
    }

    static func editPrompt(from userText: String) -> String {
        let lower = userText.lowercased()
        var parts: [String] = [
            "photorealistic inpaint edit, ONLY change the masked region, keep unmasked pixels identical",
            "seamless edges, same lighting and camera, no global rewrite of the whole image",
            userText
        ]

        if lower.contains("entferne") || lower.contains("remove") || lower.contains("lösch")
            || lower.contains("erase") || lower.contains("füll") || lower.contains("fill") {
            parts.append("remove the marked object completely, reconstruct background naturally, no leftover fragments, no ghosting")
        }
        if lower.contains("haar") || lower.contains("hair") {
            parts.append("edit hair color/style only, keep face identity")
        }
        if lower.contains("himmel") || lower.contains("sky") {
            parts.append("edit sky region, keep ground and subject")
        }
        if lower.contains("hintergrund") || lower.contains("background") {
            parts.append("edit background, keep subject sharp")
        }
        if lower.contains("rot") || lower.contains("red") { parts.append("rich red tones") }
        if lower.contains("blau") || lower.contains("blue") { parts.append("blue tones") }
        if lower.contains("grün") || lower.contains("green") { parts.append("green lush tones") }
        if lower.contains("größer") || lower.contains("bigger") { parts.append("emphasize and enlarge the described element") }
        if lower.contains("kleiner") { parts.append("reduce the described element") }

        return parts.joined(separator: ", ")
    }

    static func denoising(for userText: String) -> Double {
        let lower = userText.lowercased()
        if lower.contains("entferne") || lower.contains("remove") || lower.contains("lösch")
            || lower.contains("erase") || lower.contains("füll") {
            return 0.88
        }
        if lower.contains("ersetze") || lower.contains("replace") || lower.contains("mach ") {
            return 0.78
        }
        if lower.contains("haar") || lower.contains("hair") || lower.contains("farbe") || lower.contains("color") {
            return 0.55
        }
        if lower.contains("heller") || lower.contains("dunkler") || lower.contains("wärmer") {
            return 0.4
        }
        return 0.72
    }
}
