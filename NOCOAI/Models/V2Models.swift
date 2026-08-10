import Foundation

enum AIMode: String, CaseIterable, Identifiable, Codable {
    case auto, agent, vision, developer, writing, study, creative, image
    /// Legacy depth / Speak compat (hidden from premium picker).
    case flash, knowledge, think

    var id: String { rawValue }

    /// Depth modes for Chat / Speak (tools like Agent live in +).
    static var premiumCases: [AIMode] {
        [.auto, .think, .flash, .agent]
    }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .agent: return "Agent"
        case .vision: return "Vision"
        case .developer: return "Developer"
        case .writing: return "Writing"
        case .study: return "Study"
        case .creative: return "Creative"
        case .image: return "Bild"
        case .flash: return "Flash"
        case .knowledge: return "Wissen"
        case .think: return "Think"
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
        case .image: return "Idee → Bild"
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
        case .image: return "photo.on.rectangle.angled"
        case .flash: return "bolt.fill"
        case .knowledge: return "globe"
        case .think: return "brain"
        }
    }

    /// True for the ultra-capable Agent chat mode (task engine).
    var isAgentPower: Bool { self == .agent }

    /// In-chat image compose (like Agent — stays in Chat, not Bilder tab).
    var isImageCompose: Bool { self == .image }

    static func from(_ raw: String?) -> AIMode {
        switch (raw ?? "").lowercased() {
        case "auto", "intelligent": return .auto
        case "agent", "noco-agent", "max": return .agent
        case "vision", "sehen", "bild": return .vision
        case "developer", "dev", "coding", "code": return .developer
        case "writing", "write", "schreiben", "text": return .writing
        case "study", "lernen", "learn": return .study
        case "creative", "kreativ": return .creative
        case "image", "bildidee", "txt2img", "bild-erstellen", "create-image": return .image
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
    /// Live Knowledge: auto | off | on
    let web: String?
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

/// Companion Think-model status (FLASH stays separate; no raw model names in Plus menu).
struct ThinkModelStatusResponse: Decodable {
    let ok: Bool?
    let flashModel: String?
    let thinkModel: String?
    let thinkInstalled: Bool?
    let thinkReady: Bool?
    let recommendedThink: String?
    let message: String?
    let installCommand: String?
    let hardware: ThinkHardwareInfo?

    var isReady: Bool { thinkReady == true || thinkInstalled == true }
}

struct ThinkHardwareInfo: Decodable {
    let totalRamGb: Double?
    let freeRamGb: Double?
    let cpuCores: Int?
    let vramMiB: Int?
    let recommendedThink: String?
    let thinkReason: String?
    let avoid14b: Bool?
}

struct ThinkInstallResponse: Decodable {
    let ok: Bool?
    let name: String?
    let error: String?
    let think: ThinkModelStatusResponse?
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

/// Speed/quality presets for the single Stable Diffusion engine on the Companion.
/// Not separate models — real `steps` + resolution via existing txt2img API.
enum ImageGenMode: String, CaseIterable, Identifiable, Codable {
    case auto
    case flash
    case think

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .flash: return "Flash"
        case .think: return "Think"
        }
    }

    var emoji: String {
        switch self {
        case .auto: return "🤖"
        case .flash: return "⚡"
        case .think: return "🧠"
        }
    }

    var subtitle: String {
        switch self {
        case .auto: return "NOCO wählt Tempo oder Qualität"
        case .flash: return "Schnell · Ideen & Skizzen"
        case .think: return "Mehr Details · länger"
        }
    }

    /// Resolved engine parameters for the Companion SD pipeline.
    var engineParams: (width: Int, height: Int, steps: Int) {
        switch self {
        case .flash: return (384, 384, 5)
        case .think: return (512, 512, 18)
        case .auto: return (448, 448, 8)
        }
    }

    static func recommend(for prompt: String) -> ImageGenMode {
        let t = prompt.lowercased()
        let wantFast = ["schnell", "lustig", "meme", "skizze", "witzig", "schnell mal", "kurz", "draft", "idea"]
        let wantQuality = [
            "logo", "professionell", "detail", "hochwertig", "qualität", "quality",
            "fotorealist", "präzise", "genau", "album", "cover", "branding",
            "cinematic", "fotoreal", "4k", "ultra"
        ]
        if wantQuality.contains(where: { t.contains($0) }) { return .think }
        if wantFast.contains(where: { t.contains($0) }) { return .flash }
        // Longer prompts often need more fidelity
        if prompt.count > 160 { return .think }
        return .flash
    }

    func resolved(for prompt: String) -> ImageGenMode {
        self == .auto ? Self.recommend(for: prompt) : self
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
