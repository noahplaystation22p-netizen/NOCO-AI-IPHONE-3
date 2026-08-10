import CoreGraphics
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

    enum EraserMode: String {
        case erase
        case replace
        case custom
    }

    static func eraserMode(from userText: String, preset: EraserMode? = nil) -> EraserMode {
        if let preset, preset != .custom { return preset }
        let lower = userText.lowercased()
        if lower.contains("entferne") || lower.contains("remove") || lower.contains("lösch")
            || lower.contains("erase") || lower.contains("radier") || lower.contains("füll") {
            return .erase
        }
        if lower.contains("ersetze") || lower.contains("replace") || lower.contains("durch") {
            return .replace
        }
        return preset ?? .custom
    }

    /// Erase: reconstruct background only — no new object.
    static func erasePrompt(from userText: String = "") -> String {
        let extra = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = [
            "photorealistic inpaint, reconstruct empty background only in the masked region",
            "match surrounding lighting, texture, perspective and grain",
            "remove the marked object completely, no leftover fragments, no ghosting, no new object",
            "seamless edges, preserve unmasked pixels exactly"
        ]
        if !extra.isEmpty { parts.append(extra) }
        return parts.joined(separator: ", ")
    }

    /// Replace: subject description + perspective/lighting/scale.
    static func replacePrompt(subject: String) -> String {
        let subjectText = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            "photorealistic inpaint replacement in the masked region only",
            subjectText,
            "same perspective, lighting, scale and camera angle as the photo",
            "cast a natural soft shadow, seamless blend with surroundings",
            "preserve unmasked pixels exactly, no global rewrite"
        ].joined(separator: ", ")
    }

    static func editPrompt(from userText: String, mode: EraserMode? = nil) -> String {
        let resolved = eraserMode(from: userText, preset: mode)
        switch resolved {
        case .erase:
            return erasePrompt(from: userText)
        case .replace:
            return replacePrompt(subject: userText)
        case .custom:
            break
        }

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

    static func denoising(for userText: String, mode: EraserMode? = nil, quality: ImageGenMode = .think) -> Double {
        let resolved = eraserMode(from: userText, preset: mode)
        let think = quality == .think || quality == .auto
        switch resolved {
        case .erase:
            return think ? 0.92 : 0.88
        case .replace:
            return think ? 0.88 : 0.82
        case .custom:
            break
        }
        let lower = userText.lowercased()
        if lower.contains("entferne") || lower.contains("remove") || lower.contains("lösch")
            || lower.contains("erase") || lower.contains("füll") {
            return think ? 0.92 : 0.88
        }
        if lower.contains("ersetze") || lower.contains("replace") || lower.contains("mach ") {
            return think ? 0.88 : 0.82
        }
        if lower.contains("haar") || lower.contains("hair") || lower.contains("farbe") || lower.contains("color") {
            return 0.55
        }
        if lower.contains("heller") || lower.contains("dunkler") || lower.contains("wärmer") {
            return 0.4
        }
        return think ? 0.86 : 0.8
    }

    /// Aspect-aware SD size: longest side capped, multiples of 64.
    static func inpaintSize(for imageSize: CGSize, quality: ImageGenMode = .think) -> (width: Int, height: Int) {
        let maxSide: CGFloat = quality == .flash ? 768 : 1024
        let w0 = max(imageSize.width, 1)
        let h0 = max(imageSize.height, 1)
        let scale = min(1, maxSide / max(w0, h0))
        var w = Int((w0 * scale).rounded())
        var h = Int((h0 * scale).rounded())
        w = max(64, min(1024, (w / 64) * 64))
        h = max(64, min(1024, (h / 64) * 64))
        return (w, h)
    }

    static func inpaintSteps(mode: EraserMode, quality: ImageGenMode) -> Int {
        let think = quality == .think
        switch mode {
        case .erase: return think ? 28 : 18
        case .replace: return think ? 30 : 20
        case .custom: return think ? 28 : 18
        }
    }
}
