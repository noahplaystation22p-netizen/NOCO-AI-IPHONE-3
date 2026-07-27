import Foundation

enum ChatRole: String, Codable {
    case user
    case assistant
    case system
}

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: ChatRole
    var text: String
    let createdAt: Date
    var isStreaming: Bool

    init(id: UUID = UUID(), role: ChatRole, text: String, createdAt: Date = .now, isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.isStreaming = isStreaming
    }
}
