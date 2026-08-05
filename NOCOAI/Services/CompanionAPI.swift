import Foundation

enum CompanionAPIError: LocalizedError {
    case invalidURL
    case unauthorized
    case invalidPIN
    case unreachable
    case badHost
    case server(String)
    case network(Error)
    case decoding

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Ungültige Server-Adresse"
        case .unauthorized:
            return "Kopplung ungültig – bitte erneut verbinden"
        case .invalidPIN:
            return "PIN ungültig oder abgelaufen. Hole eine neue PIN in NOCO AI (Statusleiste → iPhone). Die PIN wechselt alle 15 Min."
        case .unreachable:
            return "PC nicht erreichbar. Gleiches WLAN? Firewall Port 4747? NOCO AI läuft?"
        case .badHost:
            return "Ungültige IP — nur die Adresse eingeben, z. B. 192.168.178.197 (ohne http://)"
        case .server(let msg):
            return msg
        case .network(let err):
            return (err as? URLError)?.code == .timedOut
                ? CompanionAPIError.unreachable.errorDescription
                : err.localizedDescription
        case .decoding:
            return "Antwort konnte nicht gelesen werden"
        }
    }
}

struct CompanionAPI {
    let baseURL: URL
    var token: String?

    let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 400
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    func ping() async throws {
        let url = baseURL.appendingPathComponent("ping")
        let (data, response) = try await session.data(from: url)
        try validate(response: response, data: data, isPairRequest: false)
        if let ping = try? decoder.decode(PingResponse.self, from: data), !ping.isAlive {
            throw CompanionAPIError.server("Server antwortet, aber Ping fehlgeschlagen")
        }
    }

    func fetchPairing() async throws -> PairingInfo {
        let url = baseURL.appendingPathComponent("pairing")
        let (data, response) = try await session.data(from: url)
        try validate(response: response, data: data, isPairRequest: false)
        return try decoder.decode(PairingInfo.self, from: data)
    }

    func pair(pin: String, deviceName: String) async throws -> PairResponse {
        let url = baseURL.appendingPathComponent("pair")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(PairRequest(pin: pin, deviceName: deviceName))
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, isPairRequest: true)
        return try decoder.decode(PairResponse.self, from: data)
    }

    func fetchStatus() async throws -> ServerStatus {
        let url = baseURL.appendingPathComponent("status")
        var request = URLRequest(url: url)
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, isPairRequest: false)
        return try decoder.decode(ServerStatus.self, from: data)
    }

    func streamChat(message: String, conversationId: String? = nil, mode: AIMode = .auto) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await chunk in streamChatV2(message: message, conversationId: conversationId, mode: mode) {
                        if let text = chunk.content, !text.isEmpty {
                            continuation.yield(text)
                        }
                        if chunk.done == true {
                            continuation.finish()
                            return
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

    func processSSELine(_ line: String, continuation: AsyncThrowingStream<String, Error>.Continuation) throws {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return }

        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            continuation.finish()
            return
        }

        guard let data = payload.data(using: .utf8),
              let chunk = try? decoder.decode(ChatStreamChunk.self, from: data) else {
            return
        }

        if let error = chunk.error, !error.isEmpty {
            throw CompanionAPIError.server(error)
        }
        if let text = chunk.content, !text.isEmpty {
            continuation.yield(text)
        }
        if chunk.done == true {
            continuation.finish()
        }
    }

    func validate(response: URLResponse, data: Data, isPairRequest: Bool) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CompanionAPIError.server("Keine Server-Antwort")
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 {
                throw isPairRequest ? CompanionAPIError.invalidPIN : CompanionAPIError.unauthorized
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            if isPairRequest && isPINError(status: http.statusCode, body: body) {
                throw CompanionAPIError.invalidPIN
            }
            if http.statusCode == 403, isPairRequest {
                throw CompanionAPIError.invalidPIN
            }
            let message = parseErrorMessage(data: data) ?? "HTTP \(http.statusCode)"
            throw CompanionAPIError.server(message)
        }
    }

    private func isPINError(status: Int, body: String) -> Bool {
        let lower = body.lowercased()
        return status == 400 || lower.contains("pin") || lower.contains("ungültig") || lower.contains("invalid")
    }

    private func parseErrorMessage(data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["error", "message", "detail"] {
                if let value = json[key] as? String, !value.isEmpty { return value }
            }
        }
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    func mapNetworkError(_ error: Error) -> Error {
        if let api = error as? CompanionAPIError { return api }
        if let urlError = error as? URLError,
           urlError.code == .cannotConnectToHost || urlError.code == .timedOut || urlError.code == .networkConnectionLost {
            return CompanionAPIError.unreachable
        }
        if let urlError = error as? URLError, urlError.code == .cannotFindHost {
            return CompanionAPIError.badHost
        }
        return CompanionAPIError.network(error)
    }
}
