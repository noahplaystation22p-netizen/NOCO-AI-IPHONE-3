import Foundation

/// Lightweight Companion chat client for the keyboard extension.
enum KeyboardAIClient {
    struct ChatBody: Encodable {
        let message: String
        let stream: Bool
        let mode: String
        let source: String
        let channel: String
        let display: String
        let keyboard: Bool
    }

    enum ClientError: LocalizedError {
        case notConfigured
        case badURL
        case http(Int)
        case empty
        case decode
        case cancelled

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "PC nicht verbunden — NOCO AI App öffnen"
            case .badURL: return "Ungültige PC-Adresse"
            case .http(let c): return "PC-Fehler (\(c))"
            case .empty: return "Keine Antwort"
            case .decode: return "Antwort unlesbar"
            case .cancelled: return "Abgebrochen"
            }
        }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 28
        config.timeoutIntervalForResource = 40
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }()

    /// Preferred path: single flash response, sanitized — logs into ⌨️ Tastatur channel.
    static func rewrite(action: KeyboardAIAction, text: String) async throws -> String {
        CompanionCredentials.refreshFromDisk()
        guard CompanionCredentials.isConfigured,
              let base = CompanionCredentials.baseURL,
              let token = CompanionCredentials.token else {
            throw ClientError.notConfigured
        }
        let url = base.appendingPathComponent("chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = action.isAnswer ? 40 : 28
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            ChatBody(
                message: action.prompt(for: text),
                stream: false,
                mode: action.isAnswer ? "flash" : "flash",
                source: "keyboard",
                channel: "keyboard",
                display: action.displayLabel(for: text),
                keyboard: true
            )
        )

        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ClientError.http(code) }

        if let reply = extractReply(from: data) {
            let clean = KeyboardAIAction.sanitize(reply, action: action, original: text)
            guard !clean.isEmpty else { throw ClientError.empty }
            return clean
        }
        throw ClientError.decode
    }

    private static func extractReply(from data: Data) -> String? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let msg = obj["message"] as? [String: Any], let c = msg["content"] as? String { return c }
            if let c = obj["content"] as? String { return c }
            if let c = obj["reply"] as? String { return c }
            if let c = obj["text"] as? String { return c }
        }
        return String(data: data, encoding: .utf8)
    }
}
