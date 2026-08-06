import Foundation
import SwiftUI

enum AgentMode: String, CaseIterable, Identifiable, Codable {
    case assistant
    case work
    case developer
    case automation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .assistant: return "Assistent"
        case .work: return "Arbeit"
        case .developer: return "Entwickler"
        case .automation: return "Automation"
        }
    }

    var subtitle: String {
        switch self {
        case .assistant: return "Schreiben · Planen · Erklären"
        case .work: return "Dokumente · Recherche"
        case .developer: return "Code · Analyse"
        case .automation: return "Workflows · Trigger"
        }
    }

    var systemImage: String {
        switch self {
        case .assistant: return "sparkles"
        case .work: return "briefcase.fill"
        case .developer: return "chevron.left.forwardslash.chevron.right"
        case .automation: return "bolt.horizontal.circle.fill"
        }
    }

    var accent: Color {
        switch self {
        case .assistant: return Color(red: 0.42, green: 0.72, blue: 1.0)
        case .work: return Color(red: 0.35, green: 0.82, blue: 0.62)
        case .developer: return Color(red: 0.78, green: 0.62, blue: 0.98)
        case .automation: return Color(red: 0.98, green: 0.72, blue: 0.38)
        }
    }
}

enum AgentKind: String, CaseIterable, Identifiable, Codable {
    case general
    case smartHome = "smart_home"
    case coding
    case study
    case travel
    case finance
    case creative

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Allgemein"
        case .smartHome: return "Smart Home"
        case .coding: return "Coding"
        case .study: return "Study"
        case .travel: return "Travel"
        case .finance: return "Finance"
        case .creative: return "Creative"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Life Agent"
        case .smartHome: return "Geräte"
        case .coding: return "Code & Debug"
        case .study: return "Lernen"
        case .travel: return "Reisen"
        case .finance: return "Finanzen"
        case .creative: return "Texte & Ideen"
        }
    }
}

enum AgentQualityProfile: String, CaseIterable, Identifiable {
    case auto, fast, accurate, creative, developer, offline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .fast: return "Schnell"
        case .accurate: return "Genau"
        case .creative: return "Kreativ"
        case .developer: return "Entwickler"
        case .offline: return "Offline"
        }
    }
}

enum AgentTaskStatus: String, Codable {
    case draft
    case planning
    case running
    case awaitingConfirmation = "awaiting_confirmation"
    case completed
    case failed
    case cancelled

    var label: String {
        switch self {
        case .draft: return "Bereit"
        case .planning: return "Plant…"
        case .running: return "Arbeitet…"
        case .awaitingConfirmation: return "Bestätigung"
        case .completed: return "Fertig"
        case .failed: return "Fehler"
        case .cancelled: return "Abgebrochen"
        }
    }
}

struct AgentPendingConfirm: Codable, Equatable {
    let stepId: String
    let title: String
    let detail: String
    let tool: String
    let risk: String

    enum CodingKeys: String, CodingKey {
        case stepId, step_id
        case title, detail, tool, risk
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stepId = try c.decodeIfPresent(String.self, forKey: .stepId)
            ?? c.decodeIfPresent(String.self, forKey: .step_id)
            ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Bestätigung"
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        tool = try c.decodeIfPresent(String.self, forKey: .tool) ?? ""
        risk = try c.decodeIfPresent(String.self, forKey: .risk) ?? "medium"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(stepId, forKey: .stepId)
        try c.encode(title, forKey: .title)
        try c.encode(detail, forKey: .detail)
        try c.encode(tool, forKey: .tool)
        try c.encode(risk, forKey: .risk)
    }
}

struct AgentStep: Codable, Identifiable, Equatable {
    let id: String
    let index: Int
    let title: String
    let reason: String
    let tool: String
    var status: String
    var result: String?
    var artifactPath: String?
    let requiresConfirm: Bool

    enum CodingKeys: String, CodingKey {
        case id, index, title, reason, tool, status, result
        case artifactPath, artifact_path
        case requiresConfirm, requires_confirm
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        index = try c.decodeIfPresent(Int.self, forKey: .index) ?? 0
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Schritt"
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        tool = try c.decodeIfPresent(String.self, forKey: .tool) ?? "think"
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        result = try c.decodeIfPresent(String.self, forKey: .result)
        artifactPath = try c.decodeIfPresent(String.self, forKey: .artifactPath)
            ?? c.decodeIfPresent(String.self, forKey: .artifact_path)
        requiresConfirm = try c.decodeIfPresent(Bool.self, forKey: .requiresConfirm)
            ?? c.decodeIfPresent(Bool.self, forKey: .requires_confirm)
            ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(index, forKey: .index)
        try c.encode(title, forKey: .title)
        try c.encode(reason, forKey: .reason)
        try c.encode(tool, forKey: .tool)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(result, forKey: .result)
        try c.encodeIfPresent(artifactPath, forKey: .artifactPath)
        try c.encode(requiresConfirm, forKey: .requiresConfirm)
    }
}

struct AgentArtifact: Codable, Identifiable, Equatable {
    var id: String { path }
    let name: String
    let path: String
    let kind: String?
}

struct AgentLogEntry: Codable, Identifiable, Equatable {
    let id: String
    let at: String
    let level: String
    let message: String
    let stepId: String?

    enum CodingKeys: String, CodingKey {
        case id, at, level, message
        case stepId, step_id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        at = try c.decodeIfPresent(String.self, forKey: .at) ?? ""
        level = try c.decodeIfPresent(String.self, forKey: .level) ?? "info"
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        stepId = try c.decodeIfPresent(String.self, forKey: .stepId)
            ?? c.decodeIfPresent(String.self, forKey: .step_id)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(at, forKey: .at)
        try c.encode(level, forKey: .level)
        try c.encode(message, forKey: .message)
        try c.encodeIfPresent(stepId, forKey: .stepId)
    }
}

struct AgentTask: Codable, Identifiable, Equatable {
    let id: String
    var goal: String
    var mode: String
    var kind: String
    var status: String
    var planSummary: String
    var steps: [AgentStep]
    var currentStepIndex: Int
    var progress: Int
    var resultSummary: String?
    var artifacts: [AgentArtifact]
    var log: [AgentLogEntry]
    var pendingConfirm: AgentPendingConfirm?
    var source: String?
    var createdAt: String?
    var updatedAt: String?
    var phase: String?
    var qualityProfile: String?
    var activeModelLabel: String?
    var qualityNotes: String?

    var statusEnum: AgentTaskStatus {
        AgentTaskStatus(rawValue: status) ?? .draft
    }

    var modeEnum: AgentMode {
        AgentMode(rawValue: mode) ?? .assistant
    }

    var phaseColor: Color {
        switch (phase ?? "").lowercased() {
        case "analyzing": return Color(red: 0.35, green: 0.55, blue: 1.0) // blau
        case "planning": return Color(red: 0.62, green: 0.42, blue: 0.98) // violett
        case "executing": return Color(red: 0.98, green: 0.58, blue: 0.28) // orange
        case "reviewing": return Color(red: 0.72, green: 0.45, blue: 0.98)
        case "awaiting": return Color(red: 0.98, green: 0.78, blue: 0.32)
        case "done": return Color(red: 0.28, green: 0.86, blue: 0.55) // grün
        case "failed": return NOCOAITheme.danger
        default: return Color(red: 0.45, green: 0.72, blue: 1.0)
        }
    }

    var phaseTitle: String {
        switch (phase ?? "").lowercased() {
        case "analyzing": return "Analysiert"
        case "planning": return "Plant Lösung"
        case "executing": return "Führt aus"
        case "reviewing": return "Prüft Qualität"
        case "awaiting": return "Wartet auf dich"
        case "done": return "Fertig"
        case "failed": return "Fehler"
        default: return statusEnum.label
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, goal, mode, kind, status, steps, progress, artifacts, log, source, phase
        case planSummary, plan_summary
        case currentStepIndex, current_step_index
        case resultSummary, result_summary
        case pendingConfirm, pending_confirm
        case createdAt, created_at
        case updatedAt, updated_at
        case qualityProfile, quality_profile
        case activeModelLabel, active_model_label
        case qualityNotes, quality_notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        goal = try c.decodeIfPresent(String.self, forKey: .goal) ?? ""
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? "assistant"
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "general"
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "draft"
        planSummary = try c.decodeIfPresent(String.self, forKey: .planSummary)
            ?? c.decodeIfPresent(String.self, forKey: .plan_summary)
            ?? ""
        steps = try c.decodeIfPresent([AgentStep].self, forKey: .steps) ?? []
        currentStepIndex = try c.decodeIfPresent(Int.self, forKey: .currentStepIndex)
            ?? c.decodeIfPresent(Int.self, forKey: .current_step_index)
            ?? 0
        progress = try c.decodeIfPresent(Int.self, forKey: .progress) ?? 0
        resultSummary = try c.decodeIfPresent(String.self, forKey: .resultSummary)
            ?? c.decodeIfPresent(String.self, forKey: .result_summary)
        artifacts = try c.decodeIfPresent([AgentArtifact].self, forKey: .artifacts) ?? []
        log = try c.decodeIfPresent([AgentLogEntry].self, forKey: .log) ?? []
        pendingConfirm = try c.decodeIfPresent(AgentPendingConfirm.self, forKey: .pendingConfirm)
            ?? c.decodeIfPresent(AgentPendingConfirm.self, forKey: .pending_confirm)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
            ?? c.decodeIfPresent(String.self, forKey: .created_at)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
            ?? c.decodeIfPresent(String.self, forKey: .updated_at)
        phase = try c.decodeIfPresent(String.self, forKey: .phase)
        qualityProfile = try c.decodeIfPresent(String.self, forKey: .qualityProfile)
            ?? c.decodeIfPresent(String.self, forKey: .quality_profile)
        activeModelLabel = try c.decodeIfPresent(String.self, forKey: .activeModelLabel)
            ?? c.decodeIfPresent(String.self, forKey: .active_model_label)
        qualityNotes = try c.decodeIfPresent(String.self, forKey: .qualityNotes)
            ?? c.decodeIfPresent(String.self, forKey: .quality_notes)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(goal, forKey: .goal)
        try c.encode(mode, forKey: .mode)
        try c.encode(kind, forKey: .kind)
        try c.encode(status, forKey: .status)
        try c.encode(planSummary, forKey: .planSummary)
        try c.encode(steps, forKey: .steps)
        try c.encode(currentStepIndex, forKey: .currentStepIndex)
        try c.encode(progress, forKey: .progress)
        try c.encodeIfPresent(resultSummary, forKey: .resultSummary)
        try c.encode(artifacts, forKey: .artifacts)
        try c.encode(log, forKey: .log)
        try c.encodeIfPresent(pendingConfirm, forKey: .pendingConfirm)
        try c.encodeIfPresent(source, forKey: .source)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(phase, forKey: .phase)
        try c.encodeIfPresent(qualityProfile, forKey: .qualityProfile)
        try c.encodeIfPresent(activeModelLabel, forKey: .activeModelLabel)
        try c.encodeIfPresent(qualityNotes, forKey: .qualityNotes)
    }
}

struct AgentProject: Decodable, Identifiable, Equatable {
    let id: String
    var title: String
    var goal: String
    var progress: Int
    var notes: String?
    var relatedTaskIds: [String]?
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, goal, progress, notes
        case relatedTaskIds, related_task_ids
        case createdAt, created_at
        case updatedAt, updated_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Projekt"
        goal = try c.decodeIfPresent(String.self, forKey: .goal) ?? ""
        progress = try c.decodeIfPresent(Int.self, forKey: .progress) ?? 0
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        relatedTaskIds = try c.decodeIfPresent([String].self, forKey: .relatedTaskIds)
            ?? c.decodeIfPresent([String].self, forKey: .related_task_ids)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
            ?? c.decodeIfPresent(String.self, forKey: .created_at)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
            ?? c.decodeIfPresent(String.self, forKey: .updated_at)
    }
}

struct AgentProjectsResponse: Decodable {
    let projects: [AgentProject]?
}

struct AgentMemorySnapshot: Decodable {
    let preferences: AgentMemoryPreferences?
    let facts: [AgentMemoryFact]?
    let lastGoals: [String]?
}

struct AgentMemoryPreferences: Decodable {
    let language: String?
    let style: String?
    let confirmDangerous: Bool?
}

struct AgentMemoryFact: Decodable, Identifiable {
    var id: String { text }
    let text: String
    let at: String?
}

struct AgentTaskResponse: Decodable {
    let ok: Bool?
    let task: AgentTask?
    let error: String?
}

struct AgentTaskListResponse: Decodable {
    let tasks: [AgentTask]?
}

struct AgentWorkflow: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var trigger: String
    var action: String
    var mode: String?
    var enabled: Bool?
}
