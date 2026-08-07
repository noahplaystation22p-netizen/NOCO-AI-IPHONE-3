import ActivityKit
import AppIntents
import Foundation

extension Notification.Name {
    static let nocoStartSpeak = Notification.Name("nocoai.startSpeak")
    static let nocoStopSpeak = Notification.Name("nocoai.stopSpeak")
    static let nocoOpenImagesPrompt = Notification.Name("nocoai.openImagesPrompt")
    static let nocoOpenAgentGoal = Notification.Name("nocoai.openAgentGoal")
    static let nocoAskChat = Notification.Name("nocoai.askChat")
    static let nocoOpenVisionLive = Notification.Name("nocoai.openVisionLive")
}

/// Bridge between Shortcuts / Siri App Intents and the running SwiftUI app.
enum SpeakLaunchBridge {
    private static let pendingKey = "nocoai.pendingSpeakStart"
    private static let pendingToggleKey = "nocoai.pendingSpeakToggle"
    /// When true: start Voice AI without presenting the Speak sheet.
    private static let backgroundOnlyKey = "nocoai.pendingSpeakBackgroundOnly"

    static var pendingStart: Bool {
        get { UserDefaults.standard.bool(forKey: pendingKey) }
        set { UserDefaults.standard.set(newValue, forKey: pendingKey) }
    }

    static var pendingToggle: Bool {
        get { UserDefaults.standard.bool(forKey: pendingToggleKey) }
        set { UserDefaults.standard.set(newValue, forKey: pendingToggleKey) }
    }

    static var preferBackgroundOnly: Bool {
        get { UserDefaults.standard.bool(forKey: backgroundOnlyKey) }
        set { UserDefaults.standard.set(newValue, forKey: backgroundOnlyKey) }
    }

    static func requestStart(backgroundOnly: Bool = true) {
        pendingToggle = false
        preferBackgroundOnly = backgroundOnly
        pendingStart = true
        NotificationCenter.default.post(name: .nocoStartSpeak, object: nil)
    }

    static func requestToggle(backgroundOnly: Bool = true) {
        pendingStart = false
        preferBackgroundOnly = backgroundOnly
        pendingToggle = true
        NotificationCenter.default.post(name: .nocoStartSpeak, object: nil)
    }

    static func requestStop() {
        pendingStart = false
        pendingToggle = false
        preferBackgroundOnly = true
        NotificationCenter.default.post(name: .nocoStopSpeak, object: nil)
    }

    static func clearPending() {
        pendingStart = false
        pendingToggle = false
        preferBackgroundOnly = false
    }
}

/// Ends Voice AI from a Shortcut without requiring the Speak UI.
@MainActor
enum VoiceAIBackgroundControl {
    static func stopSilently() async {
        VoiceAISessionState.pendingStop = true
        VoiceAISessionState.publish(active: false, micOn: false, islandOn: false)
        let activities = Activity<SpeakActivityAttributes>.activities
        for act in activities {
            await act.end(nil, dismissalPolicy: .immediate)
        }
        SpeakLaunchBridge.requestStop()
    }
}


/// Cold-start / Shortcut bridges for Images, Agent, Ask.
enum NOCOLaunchBridge {
    private static let imagesKey = "nocoai.pendingOpenImages"
    private static let imagePromptKey = "nocoai.pendingImagePrompt"
    private static let agentKey = "nocoai.pendingOpenAgent"
    private static let agentGoalKey = "nocoai.pendingAgentGoal"
    private static let askKey = "nocoai.pendingAskDraft"
    private static let visionKey = "nocoai.pendingOpenVision"

    static var pendingImages: Bool {
        get { UserDefaults.standard.bool(forKey: imagesKey) }
        set { UserDefaults.standard.set(newValue, forKey: imagesKey) }
    }

    static var pendingImagePrompt: String? {
        get { UserDefaults.standard.string(forKey: imagePromptKey) }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: imagePromptKey)
            } else {
                UserDefaults.standard.removeObject(forKey: imagePromptKey)
            }
        }
    }

    static var pendingAgent: Bool {
        get { UserDefaults.standard.bool(forKey: agentKey) }
        set { UserDefaults.standard.set(newValue, forKey: agentKey) }
    }

    static var pendingAgentGoal: String? {
        get { UserDefaults.standard.string(forKey: agentGoalKey) }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: agentGoalKey)
            } else {
                UserDefaults.standard.removeObject(forKey: agentGoalKey)
            }
        }
    }

    static var pendingAskDraft: String? {
        get { UserDefaults.standard.string(forKey: askKey) }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: askKey)
            } else {
                UserDefaults.standard.removeObject(forKey: askKey)
            }
        }
    }

    static var pendingVision: Bool {
        get { UserDefaults.standard.bool(forKey: visionKey) }
        set { UserDefaults.standard.set(newValue, forKey: visionKey) }
    }

    static func requestImages(prompt: String? = nil) {
        pendingImages = true
        pendingImagePrompt = prompt
        NotificationCenter.default.post(
            name: .nocoOpenImagesPrompt,
            object: nil,
            userInfo: prompt.map { ["prompt": $0] }
        )
    }

    static func requestAgent(goal: String? = nil) {
        pendingAgent = true
        pendingAgentGoal = goal
        NotificationCenter.default.post(
            name: .nocoOpenAgentGoal,
            object: nil,
            userInfo: goal.map { ["goal": $0] }
        )
    }

    static func requestAsk(draft: String) {
        pendingAskDraft = draft
        NotificationCenter.default.post(
            name: .nocoAskChat,
            object: nil,
            userInfo: ["draft": draft]
        )
    }

    static func requestVision() {
        pendingVision = true
        NotificationCenter.default.post(name: .nocoOpenVisionLive, object: nil)
    }

    static func clearConsumed() {
        pendingImages = false
        pendingImagePrompt = nil
        pendingAgent = false
        pendingAgentGoal = nil
        pendingAskDraft = nil
        pendingVision = false
    }
}

/// Opens / toggles NOCO Voice AI — primary Action Button / Shortcuts entry.
/// Start needs a brief app wake for the microphone (Apple requirement); Stop prefers background.
struct ToggleVoiceAIIntent: AppIntent {
    static var title: LocalizedStringResource = "NOCO Voice AI"
    static var description = IntentDescription(
        "Startet oder beendet NOCO Voice AI. Ideal für den Action Button: einmal an, einmal aus."
    )
    /// Mic start requires a short app activation; UI sheet stays closed.
    static var openAppWhenRun: Bool = true

    static var parameterSummary: some ParameterSummary {
        Summary("NOCO Voice AI")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if VoiceAISessionState.isActive || SpeakLaunchBridge.pendingStart {
            await VoiceAIBackgroundControl.stopSilently()
            try? await Task.sleep(nanoseconds: 60_000_000)
            return .result(dialog: "NOCO Voice AI beendet.")
        }
        SpeakLaunchBridge.requestToggle(backgroundOnly: true)
        try? await Task.sleep(nanoseconds: 180_000_000)
        return .result(dialog: "NOCO Voice AI startet.")
    }
}

/// Opens NOCO AI and starts Voice AI — works from Shortcuts / Siri even if the app was closed.
struct StartSpeakIntent: AppIntent {
    static var title: LocalizedStringResource = "NOCO Voice AI starten"
    static var description = IntentDescription(
        "Startet NOCO Voice AI im Hintergrund. Kurz App-Wake für Mikrofon, danach Dynamic Island."
    )
    static var openAppWhenRun: Bool = true

    static var parameterSummary: some ParameterSummary {
        Summary("NOCO Voice AI starten")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SpeakLaunchBridge.requestStart(backgroundOnly: true)
        try? await Task.sleep(nanoseconds: 220_000_000)
        return .result(dialog: "NOCO Voice AI startet.")
    }
}

struct StopSpeakIntent: AppIntent {
    static var title: LocalizedStringResource = "NOCO Voice AI stoppen"
    static var description = IntentDescription("Beendet NOCO Voice AI sofort — ohne Speak-UI.")
    /// Prefer not forcing a full UI presentation when only stopping.
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await VoiceAIBackgroundControl.stopSilently()
        return .result(dialog: "NOCO Voice AI beendet.")
    }
}

struct CreateImageIntent: AppIntent {
    static var title: LocalizedStringResource = "Bild mit NOCO erstellen"
    static var description = IntentDescription("Öffnet Bildideen und übernimmt optional eine Beschreibung.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Bildbeschreibung")
    var prompt: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Bild mit NOCO erstellen")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        NOCOLaunchBridge.requestImages(prompt: (text?.isEmpty == false) ? text : nil)
        return .result(dialog: "Bildideen öffnen…")
    }
}

struct StartAgentIntent: AppIntent {
    static var title: LocalizedStringResource = "NOCO Agent starten"
    static var description = IntentDescription("Öffnet den Agent und übernimmt optional ein Ziel.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Aufgabe")
    var goal: String?

    static var parameterSummary: some ParameterSummary {
        Summary("NOCO Agent starten")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = goal?.trimmingCharacters(in: .whitespacesAndNewlines)
        NOCOLaunchBridge.requestAgent(goal: (text?.isEmpty == false) ? text : nil)
        return .result(dialog: "Agent öffnen…")
    }
}

struct AskNOCOIntent: AppIntent {
    static var title: LocalizedStringResource = "Frage NOCO"
    static var description = IntentDescription("Öffnet den Chat mit deiner Frage.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Frage")
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("Frage NOCO: \(\.$question)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            return .result(dialog: "Bitte eine Frage angeben.")
        }
        NOCOLaunchBridge.requestAsk(draft: q)
        return .result(dialog: "Chat öffnen…")
    }
}

/// Appears automatically in the Shortcuts app + Siri suggestions.
struct NOCOAIAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleVoiceAIIntent(),
            phrases: [
                "\(.applicationName) Voice AI",
                "\(.applicationName) Voice",
                "Hey \(.applicationName)",
                "Mit \(.applicationName) sprechen",
                "\(.applicationName) Sprachmodus",
                "Toggle \(.applicationName) Voice"
            ],
            shortTitle: "Voice AI",
            systemImageName: "waveform.circle.fill"
        )
        AppShortcut(
            intent: StartSpeakIntent(),
            phrases: [
                "\(.applicationName) Voice AI starten",
                "Start \(.applicationName) Voice",
                "Sprich mit \(.applicationName)"
            ],
            shortTitle: "Voice starten",
            systemImageName: "mic.circle.fill"
        )
        AppShortcut(
            intent: StopSpeakIntent(),
            phrases: [
                "\(.applicationName) Voice AI stoppen",
                "Stoppe \(.applicationName) Voice",
                "\(.applicationName) Sprachmodus beenden"
            ],
            shortTitle: "Voice stoppen",
            systemImageName: "stop.circle.fill"
        )
        AppShortcut(
            intent: CreateImageIntent(),
            phrases: [
                "Erstelle ein Bild mit \(.applicationName)",
                "\(.applicationName) Bild erstellen",
                "Bildidee mit \(.applicationName)"
            ],
            shortTitle: "Bild erstellen",
            systemImageName: "paintbrush.pointed.fill"
        )
        AppShortcut(
            intent: StartAgentIntent(),
            phrases: [
                "Starte \(.applicationName) Agent",
                "\(.applicationName) Agent",
                "Aufgabe mit \(.applicationName)"
            ],
            shortTitle: "Agent starten",
            systemImageName: "cpu.fill"
        )
        AppShortcut(
            intent: AskNOCOIntent(),
            phrases: [
                "Frage \(.applicationName)",
                "Hey \(.applicationName) frage",
                "\(.applicationName) Chat"
            ],
            shortTitle: "Frage NOCO",
            systemImageName: "bubble.left.and.bubble.right.fill"
        )
    }
}
