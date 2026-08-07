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
