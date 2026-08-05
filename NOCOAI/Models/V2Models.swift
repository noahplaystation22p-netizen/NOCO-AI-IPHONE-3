import Foundation

enum AIMode: String, CaseIterable, Identifiable, Codable {
    case flash, normal, think, auto

    var id: String { rawValue }

    var label: String {
        switch self {
        case .flash: return "Blitz"
        case .normal: return "Klar"
        case .think: return "Tiefe"
        case .auto: return "Intelligent"
        }
    }

    var subtitle: String {
        switch self {
        case .flash: return "Schnelle Antworten"
        case .normal: return "Ausgewogen"
        case .think: return "Nachdenken"
        case .auto: return "Wählt automatisch"
        }
    }

    var systemImage: String {
        switch self {
        case .flash: return "bolt.fill"
        case .normal: return "circle.lefthalf.filled"
        case .think: return "brain.head.profile"
        case .auto: return "sparkles"
        }
    }
}

struct ConversationSummary: Identifiable, Decodable, Equatable {
    let id: String
    var title: String
    let updatedAt: String?
    let type: String?
    let pinned: Bool?
    let favorite: Bool?
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

struct ImageGenerateResponse: Decodable {
    let imageUrl: String?
    let imageBase64: String?
    let mediaPath: String?
    let jobId: String?
    let conversationId: String?

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
