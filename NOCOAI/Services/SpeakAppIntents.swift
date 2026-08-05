import AppIntents
import Foundation

extension Notification.Name {
    static let nocoStartSpeak = Notification.Name("nocoai.startSpeak")
    static let nocoStopSpeak = Notification.Name("nocoai.stopSpeak")
}

/// Bridge between Shortcuts / Siri App Intents and the running SwiftUI app.
enum SpeakLaunchBridge {
    private static let pendingKey = "nocoai.pendingSpeakStart"

    static var pendingStart: Bool {
        get { UserDefaults.standard.bool(forKey: pendingKey) }
        set { UserDefaults.standard.set(newValue, forKey: pendingKey) }
    }

    static func requestStart() {
        pendingStart = true
        NotificationCenter.default.post(name: .nocoStartSpeak, object: nil)
    }

    static func requestStop() {
        pendingStart = false
        NotificationCenter.default.post(name: .nocoStopSpeak, object: nil)
    }

    static func clearPending() {
        pendingStart = false
    }
}

/// Opens NOCO AI and starts Speak — works from Shortcuts / Siri even if the app was closed.
struct StartSpeakIntent: AppIntent {
    static var title: LocalizedStringResource = "Mit NOCO sprechen"
    static var description = IntentDescription(
        "Startet den Sprachmodus. Die App kommt kurz in den Vordergrund (Mikrofon), Speak läuft danach über die Live Activity."
    )
    static var openAppWhenRun: Bool = true

    static var parameterSummary: some ParameterSummary {
        Summary("Mit NOCO sprechen")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SpeakLaunchBridge.requestStart()
        // Give the UI a moment to bind ConnectionStore after cold launch
        try? await Task.sleep(nanoseconds: 350_000_000)
        return .result(dialog: "Speak startet — sprich einfach.")
    }
}

struct StopSpeakIntent: AppIntent {
    static var title: LocalizedStringResource = "NOCO Speak stoppen"
    static var description = IntentDescription("Beendet den Sprachmodus.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SpeakLaunchBridge.requestStop()
        return .result(dialog: "Speak gestoppt.")
    }
}

/// Appears automatically in the Shortcuts app + Siri suggestions.
struct NOCOAIAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSpeakIntent(),
            phrases: [
                "Mit \(.applicationName) sprechen",
                "Sprich mit \(.applicationName)",
                "\(.applicationName) Speak starten",
                "\(.applicationName) Sprachmodus",
                "Hey \(.applicationName)",
                "Start \(.applicationName) Speak"
            ],
            shortTitle: "Speak starten",
            systemImageName: "waveform.circle.fill"
        )
        AppShortcut(
            intent: StopSpeakIntent(),
            phrases: [
                "\(.applicationName) Speak stoppen",
                "Stoppe \(.applicationName) Speak",
                "\(.applicationName) Sprachmodus beenden"
            ],
            shortTitle: "Speak stoppen",
            systemImageName: "stop.circle.fill"
        )
    }
}
