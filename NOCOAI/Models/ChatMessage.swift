import Foundation
import UIKit

enum ChatRole: String, Codable {
    case user
    case assistant
    case system
}

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let serverId: String?
    let role: ChatRole
    var text: String
    let createdAt: Date
    var isStreaming: Bool
    var imageURL: URL?
    var localImageData: Data?

    init(
        id: UUID = UUID(),
        serverId: String? = nil,
        role: ChatRole,
        text: String,
        createdAt: Date = .now,
        isStreaming: Bool = false,
        imageURL: URL? = nil,
        localImageData: Data? = nil
    ) {
        self.id = id
        self.serverId = serverId
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.isStreaming = isStreaming
        self.imageURL = imageURL
        self.localImageData = localImageData
    }
}
