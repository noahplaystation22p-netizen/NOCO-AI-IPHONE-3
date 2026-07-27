import Foundation

enum AIMode: String, CaseIterable, Identifiable, Codable {
    case flash, normal, think, auto

    var id: String { rawValue }

    var label: String {
        switch self {
        case .flash: return "Flash"
        case .normal: return "Normal"
        case .think: return "Think"
        case .auto: return "Auto"
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

    enum CodingKeys: String, CodingKey {
        case id, title, type, pinned, favorite
        case updatedAt = "updated_at"
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

    enum CodingKeys: String, CodingKey {
        case id, role, content, type
        case mediaPath = "media_path"
        case imageUrl = "image_url"
        case createdAt = "created_at"
    }

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

    enum CodingKeys: String, CodingKey {
        case message, stream, mode
        case conversationId = "conversation_id"
    }
}

struct SyncEventsResponse: Decodable {
    let events: [SyncEvent]
    let cursor: String?
    let since: String?
}

struct SyncEvent: Decodable {
    let type: String
    let conversationId: String?
    let message: ConversationMessageDTO?
    let title: String?

    enum CodingKeys: String, CodingKey {
        case type, title, message
        case conversationId = "conversation_id"
    }
}

struct FeaturesResponse: Decodable {
    let chat: Bool?
    let images: Bool?
    let code: Bool?
    let vision: Bool?
    let sync: Bool?

    var enabled: [String] {
        var list: [String] = []
        if chat == true { list.append("Chat") }
        if images == true { list.append("Bilder") }
        if code == true { list.append("Code") }
        if vision == true { list.append("Vision") }
        if sync == true { list.append("Sync") }
        return list
    }
}

struct ImageGenerateRequest: Encodable {
    let prompt: String
    let conversationId: String?

    enum CodingKeys: String, CodingKey {
        case prompt
        case conversationId = "conversation_id"
    }
}

struct ImageGenerateResponse: Decodable {
    let imageUrl: String?
    let jobId: String?
    let conversationId: String?

    enum CodingKeys: String, CodingKey {
        case imageUrl = "image_url"
        case jobId = "job_id"
        case conversationId = "conversation_id"
    }
}

struct ImageProgressResponse: Decodable {
    let percent: Double?
    let progress: Double?
    let status: String?
    let imageUrl: String?
    let done: Bool?

    enum CodingKeys: String, CodingKey {
        case percent, progress, status, done
        case imageUrl = "image_url"
    }

    var value: Double { percent ?? progress ?? 0 }
}

struct CodeSession: Identifiable, Decodable, Equatable {
    let id: String
    let title: String?
    let language: String?
    let preview: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, language, preview
        case updatedAt = "updated_at"
    }
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

    enum CodingKeys: String, CodingKey {
        case message
        case conversationId = "conversation_id"
    }
}

struct VisionUploadResult: Decodable {
    let message: ConversationMessageDTO?
    let reply: String?
    let content: String?
    let mediaPath: String?
    let imageUrl: String?
    let conversationId: String?

    enum CodingKeys: String, CodingKey {
        case message, reply, content
        case mediaPath = "media_path"
        case imageUrl = "image_url"
        case conversationId = "conversation_id"
    }

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
