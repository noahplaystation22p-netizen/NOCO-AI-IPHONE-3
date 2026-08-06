import Foundation
import SwiftUI

struct ComputerControlPermissions: Codable, Equatable {
    var enabled: Bool
    var allowMouse: Bool
    var allowKeyboard: Bool
    var allowOpenApps: Bool
    var allowWindowFocus: Bool
    var confirmEveryInput: Bool

    enum CodingKeys: String, CodingKey {
        case enabled, allowMouse, allowKeyboard, allowOpenApps, allowWindowFocus, confirmEveryInput
        case allow_mouse, allow_keyboard, allow_open_apps, allow_window_focus, confirm_every_input
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        allowMouse = try c.decodeIfPresent(Bool.self, forKey: .allowMouse)
            ?? c.decodeIfPresent(Bool.self, forKey: .allow_mouse)
            ?? false
        allowKeyboard = try c.decodeIfPresent(Bool.self, forKey: .allowKeyboard)
            ?? c.decodeIfPresent(Bool.self, forKey: .allow_keyboard)
            ?? false
        allowOpenApps = try c.decodeIfPresent(Bool.self, forKey: .allowOpenApps)
            ?? c.decodeIfPresent(Bool.self, forKey: .allow_open_apps)
            ?? false
        allowWindowFocus = try c.decodeIfPresent(Bool.self, forKey: .allowWindowFocus)
            ?? c.decodeIfPresent(Bool.self, forKey: .allow_window_focus)
            ?? true
        confirmEveryInput = try c.decodeIfPresent(Bool.self, forKey: .confirmEveryInput)
            ?? c.decodeIfPresent(Bool.self, forKey: .confirm_every_input)
            ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(allowMouse, forKey: .allowMouse)
        try c.encode(allowKeyboard, forKey: .allowKeyboard)
        try c.encode(allowOpenApps, forKey: .allowOpenApps)
        try c.encode(allowWindowFocus, forKey: .allowWindowFocus)
        try c.encode(confirmEveryInput, forKey: .confirmEveryInput)
    }
}

struct ComputerActionLogEntry: Codable, Identifiable, Equatable {
    let id: String
    let at: String
    let kind: String
    let title: String
    let detail: String
    let ok: Bool
    let risk: String
}

struct ComputerControlStatus: Decodable, Equatable {
    var ok: Bool?
    var platform: String?
    var supported: Bool
    var enabled: Bool
    var paused: Bool
    var phase: String
    var phaseLabel: String
    var currentAction: String?
    var permissions: ComputerControlPermissions?
    var lastError: String?
    var actionCount: Int?
    var recentActions: [ComputerActionLogEntry]
    var limitations: [String]
    var capabilities: [String]

    enum CodingKeys: String, CodingKey {
        case ok, platform, supported, enabled, paused, phase
        case phaseLabel, phase_label
        case currentAction, current_action
        case permissions, lastError, last_error
        case actionCount, action_count
        case recentActions, recent_actions
        case limitations, capabilities
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok)
        platform = try c.decodeIfPresent(String.self, forKey: .platform)
        supported = try c.decodeIfPresent(Bool.self, forKey: .supported) ?? false
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        phase = try c.decodeIfPresent(String.self, forKey: .phase) ?? "idle"
        phaseLabel = try c.decodeIfPresent(String.self, forKey: .phaseLabel)
            ?? c.decodeIfPresent(String.self, forKey: .phase_label)
            ?? "Bereit"
        currentAction = try c.decodeIfPresent(String.self, forKey: .currentAction)
            ?? c.decodeIfPresent(String.self, forKey: .current_action)
        permissions = try c.decodeIfPresent(ComputerControlPermissions.self, forKey: .permissions)
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
            ?? c.decodeIfPresent(String.self, forKey: .last_error)
        actionCount = try c.decodeIfPresent(Int.self, forKey: .actionCount)
            ?? c.decodeIfPresent(Int.self, forKey: .action_count)
        recentActions = try c.decodeIfPresent([ComputerActionLogEntry].self, forKey: .recentActions)
            ?? c.decodeIfPresent([ComputerActionLogEntry].self, forKey: .recent_actions)
            ?? []
        limitations = try c.decodeIfPresent([String].self, forKey: .limitations) ?? []
        capabilities = try c.decodeIfPresent([String].self, forKey: .capabilities) ?? []
    }

    var phaseColor: Color {
        switch phase.lowercased() {
        case "analyzing_screen": return Color(red: 0.35, green: 0.55, blue: 1.0)
        case "recognizing", "planning": return Color(red: 0.62, green: 0.42, blue: 0.98)
        case "executing": return Color(red: 0.98, green: 0.58, blue: 0.28)
        case "verifying": return Color(red: 0.72, green: 0.45, blue: 0.98)
        case "done": return Color(red: 0.28, green: 0.86, blue: 0.55)
        case "paused", "awaiting_confirm": return Color(red: 0.98, green: 0.78, blue: 0.32)
        case "failed": return NOCOAITheme.danger
        default: return Color(red: 0.45, green: 0.72, blue: 1.0)
        }
    }
}
