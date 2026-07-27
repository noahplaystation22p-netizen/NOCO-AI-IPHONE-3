import Foundation

enum CompanionAPIError: LocalizedError {
    case invalidURL
    case unauthorized
    case server(String)
    case network(Error)
    case decoding

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Ungültige Server-Adresse"
        case .unauthorized: return "Kopplung ungültig – bitte erneut verbinden"
        case .server(let msg): return msg
        case .network(let err): return err.localizedDescription
        case .decoding: return "Antwort konnte nicht gelesen werden"
        }
    }
}

struct CompanionAPI {
    let baseURL: URL
    var token: String?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func fetchPairing() async throws -> PairingInfo {
        let url = baseURL.appendingPathComponent("pairing")
        let (data, response) = try await session.data(from: url)
        try validate(response: response, data: data)
        return try decoder.decode(PairingInfo.self, from: data)
    }

    func pair(pin: String, deviceName: String) async throws -> PairResponse {
        let url = baseURL.appendingPathComponent("pair")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PairRequest(pin: pin, deviceName: deviceName))
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(PairResponse.self, from: data)
    }

    func fetchStatus() async throws -> ServerStatus {
        let url = baseURL.appendingPathComponent("status")
        var request = URLRequest(url: url)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(ServerStatus.self, from: data)
    }

    func streamChat(message: String, conversationId: String? = nil) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = baseURL.appendingPathComponent("chat")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
                    request.httpBody = try JSONEncoder().encode(ChatRequest(message: message, conversationId: conversationId))

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw CompanionAPIError.server("Keine Server-Antwort")
                    }
                    guard (200...299).contains(http.statusCode) else {
                        if http.statusCode == 401 { throw CompanionAPIError.unauthorized }
                        throw CompanionAPIError.server("Chat-Fehler (\(http.statusCode))")
                    }

                    var buffer = ""
                    for try await byte in bytes {
                        let char = Character(UnicodeScalar(byte))
                        buffer.append(char)
                        while let range = buffer.range(of: "\n") {
                            let line = String(buffer[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                            buffer.removeSubrange(..<range.upperBound)
                            if let chunk = parseSSELine(line) {
                                if let error = chunk.error, !error.isEmpty {
                                    throw CompanionAPIError.server(error)
                                }
                                if let text = chunk.delta ?? chunk.content, !text.isEmpty {
                                    continuation.yield(text)
                                }
                                if chunk.done == true {
                                    continuation.finish()
                                    return
                                }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func parseSSELine(_ line: String) -> ChatStreamChunk? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return ChatStreamChunk(content: nil, delta: nil, done: true, error: nil) }
        guard let data = payload.data(using: .utf8) else { return nil }
        return try? decoder.decode(ChatStreamChunk.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CompanionAPIError.server("Keine Server-Antwort")
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 { throw CompanionAPIError.unauthorized }
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw CompanionAPIError.server(message)
        }
    }
}
