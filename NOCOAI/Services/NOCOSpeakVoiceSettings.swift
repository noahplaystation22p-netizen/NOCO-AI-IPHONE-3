import AVFoundation
import Foundation

/// Special picker id — not an AVSpeechSynthesisVoice identifier.
enum NOCOSpeakVoiceID {
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
        case .natural: return "Ausgewogen · KI-Assistent"
        case .fast: return "Tempo zuerst"
        case .calm: return "Weich · entspannt"
        case .professional: return "Klar · präzise"
        }
    }

    /// Multiplier on base utterance rate.
    var rateFactor: Float {
        switch self {
        case .natural: return 1.0
        case .fast: return 1.14
        case .calm: return 0.9
        case .professional: return 0.96
        }
    }

    var pitchBias: Float {
        switch self {
        case .natural: return 0.0
        case .fast: return 0.02
        case .calm: return -0.03
        case .professional: return -0.01
        }
    }

    var pauseScale: Double {
        switch self {
        case .natural: return 1.0
        case .fast: return 0.55
        case .calm: return 1.25
        case .professional: return 0.85
        }
    }
}

/// Persisted Speak voice preferences — fast, on-device AVSpeech only.
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

    /// Resolved AVSpeech rate for current settings.
    static func resolvedRate(naturalBase: Bool) -> Float {
        // Keep Natural near default speaking rate — 0.78 felt deep/slow vs Settings preview.
        let base = naturalBase
            ? AVSpeechUtteranceDefaultSpeechRate * 0.98
            : AVSpeechUtteranceDefaultSpeechRate * 0.95
        let styled = base * style.rateFactor * rateMultiplier
        return min(AVSpeechUtteranceMaximumSpeechRate * 0.92, max(AVSpeechUtteranceMinimumSpeechRate * 1.05, styled))
    }

    static func resolvedPitch(naturalBase: Bool) -> Float {
        let base: Float = naturalBase ? 1.04 : 1.02
        return min(1.2, max(0.85, base + style.pitchBias + (pitchMultiplier - 1.0)))
    }

    static func resolvedPrePause(naturalBase: Bool) -> TimeInterval {
        let base = naturalBase ? 0.08 : 0.06
        return base * style.pauseScale
    }

    static func resolvedPostPause(naturalBase: Bool) -> TimeInterval {
        let base = naturalBase ? 0.06 : 0.04
        return base * style.pauseScale
    }

    static func resolvedInterChunkPause(naturalBase: Bool) -> TimeInterval {
        let base = naturalBase ? 0.07 : 0.05
        return base * style.pauseScale
    }

    /// Soft gain — Natural uses slightly less harsh amplification.
    static func resolvedGain(naturalBase: Bool) -> Float {
        naturalBase ? 2.15 : 2.6
    }
}
