import Foundation

/// Lightweight Companion chat client for the keyboard extension.
enum KeyboardAIClient {
    struct ChatBody: Encodable {
        let message: String
        let stream: Bool
        let mode: String
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
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// Non-streaming flash rewrite — returns the full rewritten text.
    static func rewrite(action: KeyboardAIAction, text: String) async throws -> String {
        guard CompanionCredentials.isConfigured,
              let base = CompanionCredentials.baseURL,
              let token = CompanionCredentials.token else {
            throw ClientError.notConfigured
        }
        let url = base.appendingPathComponent("chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            ChatBody(message: action.prompt(for: text), stream: false, mode: "flash")
        )

        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ClientError.http(code) }

        if let text = extractReply(from: data) {
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { throw ClientError.empty }
            return clean
        }
        throw ClientError.decode
    }

    /// Streaming rewrite — yields text deltas as they arrive (SSE from Companion).
    static func streamRewrite(
        action: KeyboardAIAction,
        text: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard CompanionCredentials.isConfigured,
                          let base = CompanionCredentials.baseURL,
                          let token = CompanionCredentials.token else {
                        throw ClientError.notConfigured
                    }
                    let url = base.appendingPathComponent("chat")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 60
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONEncoder().encode(
                        ChatBody(message: action.prompt(for: text), stream: true, mode: "flash")
                    )

                    let (bytes, response) = try await session.bytes(for: request)
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(code) else { throw ClientError.http(code) }

                    var gotContent = false
                    for try await line in bytes.lines {
                        if Task.isCancelled { throw ClientError.cancelled }
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.hasPrefix("data:") else { continue }
                        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            continue
                        }
                        if let err = obj["error"] as? String, !err.isEmpty {
                            throw ClientError.http(502)
                        }
                        if let chunk = obj["content"] as? String, !chunk.isEmpty {
                            gotContent = true
                            continuation.yield(chunk)
                        }
                        if obj["done"] as? Bool == true { break }
                    }
                    if !gotContent {
                        // Fallback: some servers may not stream — do a one-shot
                        let full = try await rewrite(action: action, text: text)
                        continuation.yield(full)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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
