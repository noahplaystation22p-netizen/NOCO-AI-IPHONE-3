import AudioToolbox
import UIKit

/// Premium haptic vocabulary — soft, layered, Apple-like.
enum HapticService {
    private static let lightGen = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGen = UIImpactFeedbackGenerator(style: .medium)
    private static let softGen = UIImpactFeedbackGenerator(style: .soft)
    private static let rigidGen = UIImpactFeedbackGenerator(style: .rigid)
    private static let heavyGen = UIImpactFeedbackGenerator(style: .heavy)
    private static let notifyGen = UINotificationFeedbackGenerator()
    private static let selectGen = UISelectionFeedbackGenerator()
    private static var lastStreamTick = Date.distantPast
    private static var lastSpeakCue = Date.distantPast
    private static var lastWhisper = Date.distantPast

    static func prepare() {
        lightGen.prepare()
        mediumGen.prepare()
        softGen.prepare()
        rigidGen.prepare()
        heavyGen.prepare()
        notifyGen.prepare()
        selectGen.prepare()
    }

    // MARK: - Core

    static func light() {
        lightGen.impactOccurred(intensity: 0.62)
        lightGen.prepare()
    }

    static func medium() {
        mediumGen.impactOccurred(intensity: 0.82)
        mediumGen.prepare()
    }

    static func soft() {
        softGen.impactOccurred(intensity: 0.55)
        softGen.prepare()
    }

    static func rigid() {
        rigidGen.impactOccurred(intensity: 0.95)
        rigidGen.prepare()
    }

    static func selection() {
        selectGen.selectionChanged()
        selectGen.prepare()
    }

    static func success() {
        notifyGen.notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            softGen.impactOccurred(intensity: 0.4)
        }
        notifyGen.prepare()
    }

    static func error() {
        notifyGen.notificationOccurred(.error)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            rigidGen.impactOccurred(intensity: 0.7)
        }
        notifyGen.prepare()
    }

    static func warning() {
        notifyGen.notificationOccurred(.warning)
        notifyGen.prepare()
    }

    // MARK: - Premium patterns

    /// Ultra-light tick for scrubbing / streaming (throttled).
    static func whisper() {
        let now = Date()
        guard now.timeIntervalSince(lastWhisper) > 0.08 else { return }
        lastWhisper = now
        softGen.impactOccurred(intensity: 0.22)
    }

    /// Soft bloom — sheet open / reveal.
    static func open() {
        softGen.impactOccurred(intensity: 0.45)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
            lightGen.impactOccurred(intensity: 0.55)
        }
        softGen.prepare()
    }

    /// Gentle close.
    static func dismiss() {
        softGen.impactOccurred(intensity: 0.4)
        softGen.prepare()
    }

    /// Tab / navigation change.
    static func navigate() {
        selectGen.selectionChanged()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            softGen.impactOccurred(intensity: 0.35)
        }
        selectGen.prepare()
    }

    /// Primary CTA (send, start speak, connect).
    static func send() {
        mediumGen.impactOccurred(intensity: 0.95)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.055) {
            softGen.impactOccurred(intensity: 0.55)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            lightGen.impactOccurred(intensity: 0.35)
        }
        mediumGen.prepare()
    }

    /// Toggle / switch flip.
    static func toggle() {
        softGen.impactOccurred(intensity: 0.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            selectGen.selectionChanged()
        }
        softGen.prepare()
    }

    /// Long-press acknowledge.
    static func longPress() {
        rigidGen.impactOccurred(intensity: 0.75)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            softGen.impactOccurred(intensity: 0.45)
        }
        rigidGen.prepare()
    }

    /// Mode chip change (Blitz / Wissen / …).
    static func modeChange() {
        selectGen.selectionChanged()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            lightGen.impactOccurred(intensity: 0.5)
        }
        selectGen.prepare()
    }

    /// Image / camera snap.
    static func imageSnap() {
        rigidGen.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            softGen.impactOccurred(intensity: 0.5)
        }
        rigidGen.prepare()
    }

    /// Pairing / connection celebration.
    static func pairSuccess() {
        notifyGen.notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            softGen.impactOccurred(intensity: 0.55)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            lightGen.impactOccurred(intensity: 0.7)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            softGen.impactOccurred(intensity: 0.4)
        }
        notifyGen.prepare()
    }

    /// Incoming assistant bubble.
    static func messageReceived() {
        softGen.impactOccurred(intensity: 0.48)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            lightGen.impactOccurred(intensity: 0.28)
        }
        softGen.prepare()
    }

    /// Streaming token tick (throttled).
    static func streamTick() {
        let now = Date()
        guard now.timeIntervalSince(lastStreamTick) > 0.14 else { return }
        lastStreamTick = now
        softGen.impactOccurred(intensity: 0.2)
    }

    /// Speak start/end cue.
    static func speakCue() {
        let now = Date()
        guard now.timeIntervalSince(lastSpeakCue) > 0.35 else { return }
        lastSpeakCue = now
        AudioServicesPlaySystemSound(1057)
        softGen.impactOccurred(intensity: 0.65)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
            lightGen.impactOccurred(intensity: 0.4)
        }
        softGen.prepare()
    }

    /// Focus gained on input field.
    static func focus() {
        softGen.impactOccurred(intensity: 0.32)
        softGen.prepare()
    }
}
