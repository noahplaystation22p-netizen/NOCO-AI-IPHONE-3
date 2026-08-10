import AVFoundation
import Foundation

/// Special picker id — not an AVSpeechSynthesisVoice identifier.
enum NOCOSpeakVoiceID {
    /// Natural AI Voice — best on-device neural German + conversational prosody pipeline.
    static let natural = "nocoai.natural"
    static let automatic = ""
}

/// Delivery style for Speak TTS (works with any selected voice; strongest with Natural).
enum NOCOSpeakVoiceStyle: String, CaseIterable, Identifiable {
    case natural
    case fast
    case calm
    case professional

    var id: String { rawValue }

    var label: String {
        switch self {
        case .natural: return "Natürlich"
        case .fast: return "Schnell"
        case .calm: return "Ruhig"
        case .professional: return "Professionell"
        }
    }

    var subtitle: String {
        switch self {
        case .natural: return "KI-Assistent · lebendig"
        case .fast: return "Tempo zuerst"
        case .calm: return "Weich · entspannt"
        case .professional: return "Klar · präzise"
        }
    }

    var rateFactor: Float {
        switch self {
        case .natural: return 1.0
        case .fast: return 1.12
        case .calm: return 0.9
        case .professional: return 0.96
        }
    }

    var pitchBias: Float {
        switch self {
        case .natural: return 0.0
        case .fast: return 0.015
        case .calm: return -0.025
        case .professional: return -0.01
        }
    }

    var pauseScale: Double {
        switch self {
        case .natural: return 1.0
        case .fast: return 0.5
        case .calm: return 1.2
        case .professional: return 0.82
        }
    }
}

/// Per-chunk delivery — varies rate/pitch/pauses so speech is not monotone.
struct NOCOSpeakChunkProsody {
    var rate: Float
    var pitch: Float
    var prePause: TimeInterval
    var postPause: TimeInterval
}

/// Persisted Speak voice preferences — fast, on-device AVSpeech only (no heavy PC TTS).
enum NOCOSpeakVoiceSettings {
    private static let voiceKey = "nocoai.voiceId"
    private static let styleKey = "nocoai.speakVoiceStyle"
    private static let rateKey = "nocoai.speakRate"
    private static let pitchKey = "nocoai.speakPitch"

    static var voiceIdentifier: String {
        get { UserDefaults.standard.string(forKey: voiceKey) ?? NOCOSpeakVoiceID.natural }
        set { UserDefaults.standard.set(newValue, forKey: voiceKey) }
    }

    static var style: NOCOSpeakVoiceStyle {
        get {
            let raw = UserDefaults.standard.string(forKey: styleKey) ?? NOCOSpeakVoiceStyle.natural.rawValue
            return NOCOSpeakVoiceStyle(rawValue: raw) ?? .natural
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: styleKey) }
    }

    /// 0.7 … 1.2 relative to Natural base rate.
    static var rateMultiplier: Float {
        get {
            let v = UserDefaults.standard.object(forKey: rateKey) as? Float
            return min(1.2, max(0.7, v ?? 1.0))
        }
        set { UserDefaults.standard.set(newValue, forKey: rateKey) }
    }

    /// 0.85 … 1.2 pitch multiplier.
    static var pitchMultiplier: Float {
        get {
            let v = UserDefaults.standard.object(forKey: pitchKey) as? Float
            return min(1.2, max(0.85, v ?? 1.0))
        }
        set { UserDefaults.standard.set(newValue, forKey: pitchKey) }
    }

    static var usesNaturalPipeline: Bool {
        voiceIdentifier == NOCOSpeakVoiceID.natural
    }

    static func ensureDefaults() {
        if UserDefaults.standard.object(forKey: voiceKey) == nil {
            UserDefaults.standard.set(NOCOSpeakVoiceID.natural, forKey: voiceKey)
        }
        if UserDefaults.standard.object(forKey: styleKey) == nil {
            UserDefaults.standard.set(NOCOSpeakVoiceStyle.natural.rawValue, forKey: styleKey)
        }
    }

    static func resolvedRate(naturalBase: Bool) -> Float {
        // Natural slightly above default — modern assistants feel a bit brisker than textbook TTS.
        let base = naturalBase
            ? AVSpeechUtteranceDefaultSpeechRate * 1.02
            : AVSpeechUtteranceDefaultSpeechRate * 0.96
        let styled = base * style.rateFactor * rateMultiplier
        return min(AVSpeechUtteranceMaximumSpeechRate * 0.9, max(AVSpeechUtteranceMinimumSpeechRate * 1.08, styled))
    }

    static func resolvedPitch(naturalBase: Bool) -> Float {
        // Light lift avoids the “deep robot announcer” feel without sounding cartoonish.
        let base: Float = naturalBase ? 1.06 : 1.02
        return min(1.18, max(0.88, base + style.pitchBias + (pitchMultiplier - 1.0)))
    }

    static func resolvedPrePause(naturalBase: Bool) -> TimeInterval {
        let base = naturalBase ? 0.05 : 0.05
        return base * style.pauseScale
    }

    static func resolvedPostPause(naturalBase: Bool) -> TimeInterval {
        let base = naturalBase ? 0.14 : 0.08
        return base * style.pauseScale
    }

    static func resolvedInterChunkPause(naturalBase: Bool) -> TimeInterval {
        let base = naturalBase ? 0.09 : 0.06
        return base * style.pauseScale
    }

    static func resolvedGain(naturalBase: Bool) -> Float {
        naturalBase ? 2.05 : 2.55
    }

    /// Variable prosody per phrase — Natural pipeline only varies strongly.
    static func chunkProsody(
        text: String,
        index: Int,
        total: Int,
        naturalBase: Bool
    ) -> NOCOSpeakChunkProsody {
        let baseRate = resolvedRate(naturalBase: naturalBase)
        let basePitch = resolvedPitch(naturalBase: naturalBase)
        let preBase = index == 0 ? resolvedPrePause(naturalBase: naturalBase) : resolvedInterChunkPause(naturalBase: naturalBase)
        let postBase = resolvedPostPause(naturalBase: naturalBase)

        guard naturalBase else {
            return NOCOSpeakChunkProsody(rate: baseRate, pitch: basePitch, prePause: preBase, postPause: postBase)
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let len = trimmed.count
        var rate = baseRate
        var pitch = basePitch
        var pre = preBase
        var post = postBase

        // Short affirmations → slightly quicker, warmer.
        if len <= 28, lower.range(of: #"^(ja|nein|klar|genau|okay|ok|gut|passt|super|richtig)\b"#, options: .regularExpression) != nil {
            rate *= 1.06
            pitch += 0.03
            post *= 0.75
        }
        // Questions → gentle rise, tiny hold before.
        if trimmed.hasSuffix("?") {
            pitch += 0.045
            rate *= 0.97
            pre += 0.04
            post += 0.05
        }
        // Exclamations → a bit brighter.
        if trimmed.hasSuffix("!") {
            pitch += 0.025
            rate *= 1.03
        }
        // Longer explanatory clauses → slightly slower + breath after.
        if len > 110 {
            rate *= 0.94
            post += 0.06
        } else if len > 70 {
            rate *= 0.97
            post += 0.03
        }
        // Comma-ended mid thought → micro pause, not a full stop.
        if trimmed.hasSuffix(",") {
            post = max(0.05, post * 0.55)
            rate *= 0.99
        }
        // Sentence transitions: first chunk starts promptly; later chunks get a soft breath.
        if index > 0 {
            pre = max(0.06, pre + 0.03)
        }
        if index == total - 1, total > 1 {
            post += 0.04
        }
        // Mild alternating contour so consecutive sentences don't share one melody.
        if index % 2 == 1 {
            pitch -= 0.015
            rate *= 0.985
        } else if index > 0 {
            pitch += 0.01
        }

        rate = min(AVSpeechUtteranceMaximumSpeechRate * 0.9, max(AVSpeechUtteranceMinimumSpeechRate * 1.05, rate))
        pitch = min(1.2, max(0.88, pitch))
        return NOCOSpeakChunkProsody(rate: rate, pitch: pitch, prePause: pre, postPause: post)
    }
}
