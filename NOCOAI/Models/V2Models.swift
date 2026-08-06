import Foundation

enum AIMode: String, CaseIterable, Identifiable, Codable {
    case auto, agent, vision, developer, writing, study, creative
    /// Legacy depth / Speak compat (hidden from premium picker).
    case flash, knowledge, think

    var id: String { rawValue }

    /// Modes shown in the premium picker.
    static var premiumCases: [AIMode] {
        [.auto, .agent, .vision, .developer, .writing, .study, .creative]
    }

    var label: String {
        switch self {
        case .auto: return "Intelligent"
        case .agent: return "Agent"
        case .vision: return "Vision"
        case .developer: return "Developer"
        case .writing: return "Writing"
        case .study: return "Study"
        case .creative: return "Creative"
        case .flash: return "Blitz"
        case .knowledge: return "Wissen"
        case .think: return "Tiefe"
        }
    }

    var subtitle: String {
        switch self {
        case .auto: return "Wählt automatisch"
        case .agent: return "Plant & führt aus"
        case .vision: return "Bilder & Screen"
        case .developer: return "Code & Debug"
        case .writing: return "Texte & Stil"
        case .study: return "Lernen & Erklären"
        case .creative: return "Ideen & Design"
        case .flash: return "Schnelle Antworten"
        case .knowledge: return "Ohne Chat-Kontext"
        case .think: return "Nachdenken"
        }
    }

    var systemImage: String {
        switch self {
        case .auto: return "sparkles"
        case .agent: return "cpu.fill"
        case .vision: return "eye.circle.fill"
        case .developer: return "chevron.left.forwardslash.chevron.right"
        case .writing: return "pencil.line"
        case .study: return "book.fill"
        case .creative: return "paintpalette.fill"
        case .flash: return "bolt.fill"
        case .knowledge: return "globe"
        case .think: return "brain"
        }
    }

    /// True for the ultra-capable Agent chat mode (task engine).
    var isAgentPower: Bool { self == .agent }

    static func from(_ raw: String?) -> AIMode {
        switch (raw ?? "").lowercased() {
        case "auto", "intelligent": return .auto
        case "agent", "noco-agent", "max": return .agent
        case "vision", "sehen", "bild": return .vision
        case "developer", "dev", "coding", "code": return .developer
        case "writing", "write", "schreiben", "text": return .writing
        case "study", "lernen", "learn": return .study
        case "creative", "kreativ": return .creative
        case "flash", "blitz": return .flash
        case "knowledge", "wissen", "normal", "klar": return .knowledge
        case "think", "tiefe", "depth": return .think
        default: return .auto
        }
    }

    /// Accept legacy values from older builds / PC.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AIMode.from(raw)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

struct ConversationSummary: Identifiable, Decodable, Equatable {
    let id: String
    var title: String
    let updatedAt: String?
    let type: String?
    let channel: String?
    let pinned: Bool?
    let favorite: Bool?

    var isKeyboard: Bool {
        if let channel, channel.lowercased() == "keyboard" { return true }
        if let type, type.lowercased() == "keyboard" { return true }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.hasPrefix("⌨️") || t.hasPrefix("tastatur") { return true }
        // Keyboard action labels that sometimes leaked as chat titles
        let keyboardPrefixes = [
            "verbessern:", "aufräumen:", "kürzer:", "länger:", "antwort:", "satz:", "fragen:",
            "satzzeichen:", "freundlicher:", "professionell:", "übersetzen:",
            "zusammenfassen:", "liste:", "improve:", "shorten:", "cleanup:", "frage:",
            "zusammenfassung bisher", "fortsetzung (zusammenfassung)"
        ]
        return keyboardPrefixes.contains { t.hasPrefix($0) }
    }
}

struct ConversationListResponse: Decodable {
    let conversations: [ConversationSummary]?
    let items: [ConversationSummary]?

    var all: [ConversationSummary] { conversations ?? items ?? [] }
}

struct ConversationMessageDTO: Identifiable, Decodable, Equatable {
    let id: String
    let role: String
    let content: String
    let type: String?
    let mediaPath: String?
    let imageUrl: String?
    let createdAt: String?

    init(id: String, role: String, content: String, type: String? = nil, mediaPath: String? = nil, imageUrl: String? = nil, createdAt: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.type = type
        self.mediaPath = mediaPath
        self.imageUrl = imageUrl
        self.createdAt = createdAt
    }

    var isUser: Bool { role == "user" || role == "human" }
    var isGeneratedImage: Bool { type == "generated-image" || type == "image" }
    var resolvedMediaPath: String? { mediaPath ?? imageUrl }
}

struct ConversationDetail: Decodable {
    let id: String?
    let title: String?
    let messages: [ConversationMessageDTO]?

    private struct NestedConversation: Decodable {
        let id: String?
        let title: String?
        let messages: [ConversationMessageDTO]?
    }

    enum CodingKeys: String, CodingKey {
        case id, title, messages, conversation
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let nested = try? c.decode(NestedConversation.self, forKey: .conversation) {
            id = nested.id
            title = nested.title
            messages = nested.messages
        } else {
            id = try c.decodeIfPresent(String.self, forKey: .id)
            title = try c.decodeIfPresent(String.self, forKey: .title)
            messages = try c.decodeIfPresent([ConversationMessageDTO].self, forKey: .messages)
        }
    }
}

struct CreateConversationResponse: Decodable {
    let id: String?
    let title: String?
    let conversation: NestedConversation?

    struct NestedConversation: Decodable {
        let id: String
        let title: String?
    }

    var resolvedId: String? { id ?? conversation?.id }
}

struct CreateConversationRequest: Encodable {
    let title: String?
}

struct ChatRequestV2: Encodable {
    let message: String
    let conversationId: String?
    let stream: Bool
    let mode: String?
    let speak: Bool?
    /// Marks ultra Agent power requests for Companion (optional; ignored if unknown).
    let agent: Bool?
}

struct SyncEventsResponse: Decodable {
    let events: [SyncEvent]
    let cursor: String?
    let since: String?
    let typing: [TypingPresence]?
}

struct SyncEvent: Decodable {
    let type: String
    let conversationId: String?
    let message: ConversationMessageDTO?
    let title: String?
    let draftPreview: String?
    let source: String?
    let typing: Bool?
    let mode: String?
}

struct TypingPresence: Decodable, Equatable {
    let conversationId: String?
    let typing: Bool?
    let draftPreview: String?
    let source: String?
    let at: String?
}

struct FeaturesResponse: Decodable {
    let chat: Bool?
    let images: Bool?
    let code: Bool?
    let vision: Bool?
    let sync: Bool?
    let typing: Bool?

    var enabled: [String] {
        var list: [String] = []
        if chat == true { list.append("Chat") }
        if images == true { list.append("Bilder") }
        if code == true { list.append("Code") }
        if vision == true { list.append("Vision") }
        if sync == true { list.append("Sync") }
        if typing == true { list.append("Tipp-Sync") }
        return list
    }
}

struct ImageGenerateRequest: Encodable {
    let prompt: String
    let conversationId: String?
    let width: Int?
    let height: Int?
    let steps: Int?

    init(prompt: String, conversationId: String? = nil, width: Int? = 384, height: Int? = 384, steps: Int? = 6) {
        self.prompt = prompt
        self.conversationId = conversationId
        self.width = width
        self.height = height
        self.steps = steps
    }
}

struct ImageEditRequest: Encodable {
    let prompt: String
    let imageBase64: String
    let conversationId: String?
    let width: Int?
    let height: Int?
    let steps: Int?
    let denoisingStrength: Double?
    let negativePrompt: String?

    init(
        prompt: String,
        imageBase64: String,
        conversationId: String? = nil,
        width: Int? = 512,
        height: Int? = 512,
        steps: Int? = 8,
        denoisingStrength: Double? = 0.48,
        negativePrompt: String? = "blurry, low quality, watermark, text, deformed, artifacts"
    ) {
        self.prompt = prompt
        self.imageBase64 = imageBase64
        self.conversationId = conversationId
        self.width = width
        self.height = height
        self.steps = steps
        self.denoisingStrength = denoisingStrength
        self.negativePrompt = negativePrompt
    }
}

struct ImageGenerateResponse: Decodable {
    let imageUrl: String?
    let imageBase64: String?
    let mediaPath: String?
    let jobId: String?
    let conversationId: String?
    let content: String?

    var resolvedPath: String? { imageUrl ?? mediaPath }
}

struct ImageProgressResponse: Decodable {
    let percent: Double?
    let progress: Double?
    let status: String?
    let imageUrl: String?
    let done: Bool?
    let etaRelative: Double?
    let textinfo: String?
    let state: SDState?

    struct SDState: Decodable {
        let samplingStep: Int?
        let samplingSteps: Int?
        let job: String?
        let jobCount: Int?
    }

    /// 0…1 (caps below 1 until done)
    var normalizedProgress: Double {
        if let step = state?.samplingStep, let steps = state?.samplingSteps, steps > 0 {
            return min(Double(step) / Double(steps), 0.97)
        }
        if let p = progress {
            let n = p > 1 ? p / 100 : p
            return max(0, min(n, 0.97))
        }
        if let pct = percent {
            let n = pct > 1 ? pct / 100 : pct
            return max(0, min(n, 0.97))
        }
        return 0
    }

    var value: Double { normalizedProgress * 100 }

    var stepLabel: String? {
        guard let step = state?.samplingStep, let steps = state?.samplingSteps, steps > 0 else { return nil }
        return "Step \(step)/\(steps)"
    }
}

struct ImageEnginePrepareResponse: Decodable {
    let ok: Bool?
    let starting: Bool?
    let stableDiffusion: Bool?
    let message: String?
    let error: String?

    var isReady: Bool {
        if let ok, ok { return true }
        if let stableDiffusion, stableDiffusion { return true }
        return false
    }

    var displayMessage: String {
        if let message, !message.isEmpty { return message }
        if let error, !error.isEmpty { return error }
        if isReady { return "Bilder-Engine bereit" }
        return "Bilder-Engine startet noch…"
    }
}

struct ImageInterruptResponse: Decodable {
    let ok: Bool?
}

struct CodeSession: Identifiable, Decodable, Equatable {
    let id: String
    let title: String?
    let language: String?
    let preview: String?
    let updatedAt: String?
}

struct CodeSessionListResponse: Decodable {
    let sessions: [CodeSession]?
    let items: [CodeSession]?

    var all: [CodeSession] { sessions ?? items ?? [] }
}

struct CreateCodeSessionRequest: Encodable {
    let title: String?
    let language: String?
}

struct CodeChatRequest: Encodable {
    let message: String
    let stream: Bool
}

struct VisionRequest: Encodable {
    let message: String?
    let conversationId: String?
}

struct VisionUploadResult: Decodable {
    let message: ConversationMessageDTO?
    let reply: String?
    let content: String?
    let mediaPath: String?
    let imageUrl: String?
    let conversationId: String?

    var replyText: String? {
        reply ?? content ?? message?.content
    }

    var resolvedMediaPath: String? {
        mediaPath ?? imageUrl ?? message?.resolvedMediaPath
    }

    func asAssistantMessage() -> ConversationMessageDTO? {
        if let message, message.role != "user" { return message }
        guard let text = replyText, !text.isEmpty else { return nil }
        return ConversationMessageDTO(
            id: message?.id ?? UUID().uuidString,
            role: "assistant",
            content: text,
            mediaPath: resolvedMediaPath
        )
    }
}

struct MediaURLBuilder {
    let host: String
    let port: Int

    func url(for path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.lowercased().hasPrefix("http") { return URL(string: path) }
        let base = "http://\(host):\(port)"
        if path.hasPrefix("/") { return URL(string: base + path) }
        return URL(string: "\(base)/api/v1/media/\(path)")
    }
}
