import AppIntents
import Foundation

/// Opens Ask NOCO from Shortcuts / Siri on Apple Watch.
struct WatchAskNOCOIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask NOCO"
    static var description = IntentDescription("Stelle NOCO auf der Apple Watch eine kurze Frage.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Frage")
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("Frag NOCO: \(\.$question)")
    }

    func perform() async throws -> some IntentResult {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .result() }
        _ = await WatchSessionClient.shared.askFlash(trimmed, voice: false)
        return .result()
    }
}

struct WatchStartVoiceIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Voice AI"
    static var description = IntentDescription("Startet NOCO Voice AI auf der Apple Watch.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

struct WatchShowStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Show NOCO Status"
    static var description = IntentDescription("Zeigt den NOCO-Verbindungsstatus.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await WatchSessionClient.shared.refreshStatus()
        return .result()
    }
}

struct NOCOWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WatchAskNOCOIntent(),
            phrases: [
                "Frag \(.applicationName)",
                "Ask \(.applicationName)",
                "\(.applicationName) fragen"
            ],
            shortTitle: "Ask NOCO",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: WatchStartVoiceIntent(),
            phrases: ["Start Voice \(.applicationName)"],
            shortTitle: "Voice AI",
            systemImageName: "waveform"
        )
    }
}
