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

/// Soft connection state for Watch UI (no technical codes).
enum WatchLinkState: String, Codable, Equatable {
    case connected
    case connecting
    case reconnecting
    case offline
    case error

    var label: String {
        switch self {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .reconnecting: return "Reconnecting…"
        case .offline: return "Offline"
        case .error: return "NOCO ist offline."
        }
    }

    var emojiDot: String {
        switch self {
        case .connected: return "🟢"
        case .connecting, .reconnecting: return "🟡"
        case .offline, .error: return "🔴"
        }
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

    /// Watch ↔ iPhone
    var watchPhoneLink: WatchLinkState
    /// iPhone ↔ NOCO Server
    var phoneServerLink: WatchLinkState
    /// Ollama / Flash model ready on PC
    var ollamaReady: Bool
    var latencyMs: Int?
    /// User-facing last error only (never raw NWError codes).
    var lastUserError: String?
    /// Technical error for Developer Diagnostics only.
    var lastTechnicalError: String?

    static let offline = WatchStatusSnapshot(
        isOnline: false,
        connection: .offline,
        modelLabel: "Flash",
        phase: .idle,
        statusLine: "NOCO Offline",
        lastAnswer: "",
        activeJob: nil,
        phoneReachable: false,
        watchPhoneLink: .offline,
        phoneServerLink: .offline,
        ollamaReady: false,
        latencyMs: nil,
        lastUserError: nil,
        lastTechnicalError: nil
    )

    enum CodingKeys: String, CodingKey {
        case isOnline, connection, modelLabel, phase, statusLine
        case lastAnswer, activeJob, phoneReachable
        case watchPhoneLink, phoneServerLink, ollamaReady, latencyMs, lastUserError, lastTechnicalError
    }

    init(
        isOnline: Bool,
        connection: ConnectionKind,
        modelLabel: String,
        phase: Phase,
        statusLine: String,
        lastAnswer: String,
        activeJob: ActiveJob?,
        phoneReachable: Bool,
        watchPhoneLink: WatchLinkState = .offline,
        phoneServerLink: WatchLinkState = .offline,
        ollamaReady: Bool = false,
        latencyMs: Int? = nil,
        lastUserError: String? = nil,
        lastTechnicalError: String? = nil
    ) {
        self.isOnline = isOnline
        self.connection = connection
        self.modelLabel = modelLabel
        self.phase = phase
        self.statusLine = statusLine
        self.lastAnswer = lastAnswer
        self.activeJob = activeJob
        self.phoneReachable = phoneReachable
        self.watchPhoneLink = watchPhoneLink
        self.phoneServerLink = phoneServerLink
        self.ollamaReady = ollamaReady
        self.latencyMs = latencyMs
        self.lastUserError = lastUserError
        self.lastTechnicalError = lastTechnicalError
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isOnline = try c.decodeIfPresent(Bool.self, forKey: .isOnline) ?? false
        connection = try c.decodeIfPresent(ConnectionKind.self, forKey: .connection) ?? .offline
        modelLabel = try c.decodeIfPresent(String.self, forKey: .modelLabel) ?? "Flash"
        phase = try c.decodeIfPresent(Phase.self, forKey: .phase) ?? .idle
        statusLine = try c.decodeIfPresent(String.self, forKey: .statusLine) ?? "NOCO Offline"
        lastAnswer = try c.decodeIfPresent(String.self, forKey: .lastAnswer) ?? ""
        activeJob = try c.decodeIfPresent(ActiveJob.self, forKey: .activeJob)
        phoneReachable = try c.decodeIfPresent(Bool.self, forKey: .phoneReachable) ?? false
        watchPhoneLink = try c.decodeIfPresent(WatchLinkState.self, forKey: .watchPhoneLink)
            ?? (phoneReachable ? .connected : .offline)
        phoneServerLink = try c.decodeIfPresent(WatchLinkState.self, forKey: .phoneServerLink)
            ?? (isOnline ? .connected : .offline)
        ollamaReady = try c.decodeIfPresent(Bool.self, forKey: .ollamaReady) ?? isOnline
        latencyMs = try c.decodeIfPresent(Int.self, forKey: .latencyMs)
        lastUserError = try c.decodeIfPresent(String.self, forKey: .lastUserError)
        lastTechnicalError = try c.decodeIfPresent(String.self, forKey: .lastTechnicalError)
    }
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

/// Maps any technical error string to a short user-facing Watch/iPhone message.
enum WatchUserFacingError {
    static let offline = "NOCO ist offline."
    static let unreachable = "NOCO ist gerade nicht erreichbar."
    static let restoring = "Verbindung wird wiederhergestellt…"
    static let empty = "Keine Antwort erhalten."
    static let phoneAway = "iPhone nicht erreichbar."

    static func sanitize(_ raw: String?) -> String {
        guard let raw else { return unreachable }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return unreachable }
        let low = trimmed.lowercased()
        if looksTechnical(low) {
            if low.contains("timeout") || low.contains("zeitüberschreitung") {
                return restoring
            }
            if low.contains("offline") || low.contains("unreachable") {
                return offline
            }
            return unreachable
        }
        // Already friendly prose — keep, but strip embedded codes.
        return stripCodes(trimmed)
    }

    private static func looksTechnical(_ low: String) -> Bool {
        if low.contains("nwerror") { return true }
        if low.contains("http_not_allowed") { return true }
        if low.contains("connection_timeout") { return true }
        if low.contains("server_unreachable") { return true }
        if low.contains("posix") { return true }
        if low.contains("nsurlerror") { return true }
        if low.contains("error domain") { return true }
        if low.contains("code=") { return true }
        if low.hasPrefix("http_") { return true }
        if low == "unknown" || low.hasPrefix("unknown ") { return true }
        if low.range(of: #"[A-Z]{2,}(_[A-Z0-9]+)+"# , options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func stripCodes(_ text: String) -> String {
        var out = text
        let patterns = [
            #"NWError[- ]?\d+"#,
            #"HTTP_NOT_ALLOWED_BY_ATS"#,
            #"CONNECTION_TIMEOUT"#,
            #"SERVER_UNREACHABLE"#,
            #"Network\.NWError[- ]?\d+"#,
            #"\bUNKNOWN\b"#
        ]
        for p in patterns {
            out = out.replacingOccurrences(of: p, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return out
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "—- "))
    }
}
