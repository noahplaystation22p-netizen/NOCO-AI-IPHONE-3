import Foundation

/// Cross-process Voice AI session flag (App ↔ Shortcuts / Action Button).
enum VoiceAISessionState {
    static let activeKey = "nocoai.voiceAI.active"
    static let micKey = "nocoai.voiceAI.mic"
    static let islandKey = "nocoai.voiceAI.island"
    static let updatedKey = "nocoai.voiceAI.updatedAt"

    private static var suite: UserDefaults? {
        UserDefaults(suiteName: CompanionCredentials.appGroupId) ?? .standard
    }

    static var isActive: Bool {
        suite?.bool(forKey: activeKey) ?? false
    }

    static func publish(active: Bool, micOn: Bool = false, islandOn: Bool = false) {
        let s = suite
        s?.set(active, forKey: activeKey)
        s?.set(micOn, forKey: micKey)
        s?.set(islandOn, forKey: islandKey)
        s?.set(Date().timeIntervalSince1970, forKey: updatedKey)
        s?.synchronize()
    }
}
