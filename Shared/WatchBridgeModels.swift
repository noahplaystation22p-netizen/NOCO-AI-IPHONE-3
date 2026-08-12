import Foundation

/// Shared Watch ↔ iPhone message envelope (JSON over WatchConnectivity).
enum WatchBridgeAction: String, Codable {
    case ask
    case askReply
    case voiceAsk
    case voiceReply
    case statusSnapshot
    case statusRequest
    case lastAnswer
    case ping
    case pong
    case openOnPhone
}

struct WatchBridgeMessage: Codable {
    let action: WatchBridgeAction
    let requestId: String?
    let text: String?
    let error: String?
    let snapshot: WatchStatusSnapshot?
    let timestamp: Date

    init(
        action: WatchBridgeAction,
        requestId: String? = nil,
        text: String? = nil,
        error: String? = nil,
        snapshot: WatchStatusSnapshot? = nil,
        timestamp: Date = Date()
    ) {
        self.action = action
        self.requestId = requestId
        self.text = text
        self.error = error
        self.snapshot = snapshot
        self.timestamp = timestamp
    }
}

/// Compact status pushed to the Watch (no heavy payloads).
struct WatchStatusSnapshot: Codable, Equatable {
    enum ConnectionKind: String, Codable {
        case local
        case remote
        case offline
    }

    enum Phase: String, Codable {
        case idle
        case listening
        case thinking
        case speaking
        case connecting
        case error
    }

    struct ActiveJob: Codable, Equatable {
        var kind: String
        var title: String
        var progress: Double
        var detail: String?
    }

    var isOnline: Bool
    var connection: ConnectionKind
    var modelLabel: String
    var phase: Phase
    var statusLine: String
    var lastAnswer: String
    var activeJob: ActiveJob?
    var phoneReachable: Bool

    static let offline = WatchStatusSnapshot(
        isOnline: false,
        connection: .offline,
        modelLabel: "Flash",
        phase: .idle,
        statusLine: "NOCO Offline",
        lastAnswer: "",
        activeJob: nil,
        phoneReachable: false
    )
}

enum WatchBridgeCodec {
    static func encode(_ message: WatchBridgeMessage) -> [String: Any] {
        let data = (try? JSONEncoder().encode(message)) ?? Data()
        return ["payload": data]
    }

    static func decode(_ dict: [String: Any]) -> WatchBridgeMessage? {
        guard let data = dict["payload"] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchBridgeMessage.self, from: data)
    }
}
