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
    /// Soft label for “Verwendetes Modell” (may be a mode hint).
    var modelLabel: String?
    /// True when Companion Live Knowledge / web context was used.
    var webUsed: Bool
    var webSourceTitles: [String]

    init(
        id: UUID = UUID(),
        serverId: String? = nil,
        role: ChatRole,
        text: String,
        createdAt: Date = .now,
        isStreaming: Bool = false,
        imageURL: URL? = nil,
        localImageData: Data? = nil,
        modelLabel: String? = nil,
        webUsed: Bool = false,
        webSourceTitles: [String] = []
    ) {
        self.id = id
        self.serverId = serverId
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.isStreaming = isStreaming
        self.imageURL = imageURL
        self.localImageData = localImageData
        self.modelLabel = modelLabel
        self.webUsed = webUsed
        self.webSourceTitles = webSourceTitles
    }
}
