import AudioToolbox
import UIKit

enum HapticService {
    private static let lightGen = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGen = UIImpactFeedbackGenerator(style: .medium)
    private static let softGen = UIImpactFeedbackGenerator(style: .soft)
    private static let rigidGen = UIImpactFeedbackGenerator(style: .rigid)
    private static let notifyGen = UINotificationFeedbackGenerator()
    private static let selectGen = UISelectionFeedbackGenerator()
    private static var lastStreamTick = Date.distantPast
    private static var lastSpeakCue = Date.distantPast

    static func prepare() {
        lightGen.prepare()
        mediumGen.prepare()
        softGen.prepare()
        notifyGen.prepare()
        selectGen.prepare()
    }

    static func light() {
        lightGen.impactOccurred(intensity: 0.7)
        lightGen.prepare()
    }

    static func medium() {
        mediumGen.impactOccurred(intensity: 0.85)
        mediumGen.prepare()
    }

    static func soft() {
        softGen.impactOccurred(intensity: 0.6)
        softGen.prepare()
    }

    static func rigid() {
        rigidGen.impactOccurred(intensity: 1.0)
        rigidGen.prepare()
    }

    static func selection() {
        selectGen.selectionChanged()
        selectGen.prepare()
    }

    static func send() {
        mediumGen.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            softGen.impactOccurred(intensity: 0.5)
        }
        mediumGen.prepare()
    }

    static func streamTick() {
        let now = Date()
        guard now.timeIntervalSince(lastStreamTick) > 0.12 else { return }
        lastStreamTick = now
        softGen.impactOccurred(intensity: 0.35)
    }

    static func success() {
        notifyGen.notificationOccurred(.success)
        notifyGen.prepare()
    }

    static func error() {
        notifyGen.notificationOccurred(.error)
        notifyGen.prepare()
    }

    static func messageReceived() {
        softGen.impactOccurred(intensity: 0.55)
        softGen.prepare()
    }

    /// Soft ding + haptic when Speak starts or ends.
    static func speakCue() {
        let now = Date()
        guard now.timeIntervalSince(lastSpeakCue) > 0.35 else { return }
        lastSpeakCue = now
        // 1057 ≈ soft “tock”; quieter than alert tones
        AudioServicesPlaySystemSound(1057)
        softGen.impactOccurred(intensity: 0.7)
        softGen.prepare()
    }
}
