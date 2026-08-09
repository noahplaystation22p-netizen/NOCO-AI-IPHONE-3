import Foundation

enum CompanionAPIError: LocalizedError {
    case invalidURL
    case unauthorized
    case invalidPIN
    case unreachable
    case badHost
    case remoteAccessDisabled
    case server(String)
    case network(Error)
    case decoding
    /// Precise classified failure (preferred over collapsing into `.unreachable`).
    case failure(ConnectionFailureCode, detail: String? = nil)

    var failureCode: ConnectionFailureCode {
        switch self {
        case .invalidURL, .badHost:
            return .invalidRemoteHost
        case .unauthorized:
            return .httpError401
        case .invalidPIN:
            return .httpError403
        case .unreachable:
            return .serverUnreachable
        case .remoteAccessDisabled:
            return .remoteAccessDisabled
        case .decoding:
            return .noServerResponse
        case .server(let msg):
            let low = msg.lowercased()
            if low.contains("http 5") || low.contains("500") || low.contains("502") || low.contains("503") {
                return .httpError5xx
            }
            if low.contains("404") || low.contains("unbekannte route") {
                return .httpError404
            }
            if low.contains("403") { return .httpError403 }
            if low.contains("401") { return .httpError401 }
            return .httpError4xx
        case .failure(let code, _):
            return code
        case .network(let err):
            return ConnectionFailureCode.classify(err)
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Ungültige Server-Adresse"
        case .unauthorized:
            return "Kopplung ungültig – bitte erneut verbinden"
        case .invalidPIN:
            return "PIN ungültig oder abgelaufen. Hole eine neue PIN in NOCO AI (Statusleiste → iPhone). Die PIN wechselt alle 15 Min."
        case .unreachable:
            return ConnectionFailureCode.serverUnreachable.userMessage
        case .badHost:
            return ConnectionFailureCode.invalidRemoteHost.userMessage
        case .remoteAccessDisabled:
            return ConnectionFailureCode.remoteAccessDisabled.userMessage
        case .server(let msg):
            return msg
        case .failure(let code, let detail):
            if let detail, !detail.isEmpty, code == .unknown {
                return "\(code.userMessage) (\(detail))"
            }
            return code.userMessage
        case .network(let err):
            // Classify precisely — never use a generic “HTTP blocked” fallback.
            let code = ConnectionFailureCode.classify(err)
            if code == .httpNotAllowedByATS {
                return code.userMessage
            }
            if code != .unknown {
                return code.userMessage
            }
            return err.localizedDescription
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
        // Longer request window so brief Wi‑Fi hiccups don't kill status/stream setup.
        config.timeoutIntervalForRequest = 45
        // Think image gen + long agent/vision jobs need headroom.
        config.timeoutIntervalForResource = 960
        // Never hang forever waiting for a path — fail fast so Voice/status can recover.
        config.waitsForConnectivity = false
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
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
        do {
            let (data, response) = try await session.data(from: url)
            try validate(response: response, data: data, isPairRequest: false)
            if let ping = try? decoder.decode(PingResponse.self, from: data), !ping.isAlive {
                throw CompanionAPIError.server("Server antwortet, aber Ping fehlgeschlagen")
            }
        } catch {
            throw mapNetworkError(error)
        }
    }

    func fetchPairing() async throws -> PairingInfo {
        let url = baseURL.appendingPathComponent("pairing")
        do {
            let (data, response) = try await session.data(from: url)
            try validate(response: response, data: data, isPairRequest: false)
            return try decoder.decode(PairingInfo.self, from: data)
        } catch {
            throw mapNetworkError(error)
        }
    }

    func pair(pin: String, deviceName: String) async throws -> PairResponse {
        let url = baseURL.appendingPathComponent("pair")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(PairRequest(pin: pin, deviceName: deviceName))
        do {
            let (data, response) = try await session.data(for: request)
            try validate(response: response, data: data, isPairRequest: true)
            return try decoder.decode(PairResponse.self, from: data)
        } catch {
            throw mapNetworkError(error)
        }
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
            if http.statusCode == 403 {
                let message = parseErrorMessage(data: data) ?? ""
                let low = message.lowercased()
                if low.contains("remote") || low.contains("tailscale") {
                    throw CompanionAPIError.remoteAccessDisabled
                }
                throw CompanionAPIError.server(message.isEmpty ? "Zugriff verweigert" : message)
            }
            var message = parseErrorMessage(data: data) ?? "HTTP \(http.statusCode)"
            if http.statusCode == 404 || message.lowercased().contains("unbekannte route") {
                message = "Unbekannte Route — NOCO AI X am PC neu starten (Companion-Update)."
            }
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
        if let urlError = error as? URLError {
            let code = ConnectionFailureCode.from(urlError: urlError)
            // Preserve precise codes — do not collapse timeout/ATS into generic unreachable.
            switch code {
            case .httpNotAllowedByATS, .connectionTimeout, .portUnreachable,
                 .firewallOrNetworkBlock, .tlsError, .dnsFailure, .invalidRemoteHost:
                return CompanionAPIError.failure(code, detail: urlError.localizedDescription)
            case .serverUnreachable:
                return CompanionAPIError.unreachable
            default:
                break
            }
        }
        let ns = error as NSError
        // Darwin / CFNetwork: POSIX EHOSTDOWN = 64 ("Host is down")
        if (ns.domain == NSPOSIXErrorDomain && ns.code == 64)
            || ns.code == 64
            || ns.localizedDescription.lowercased().contains("error 64")
            || ns.localizedDescription.lowercased().contains("host is down") {
            return CompanionAPIError.failure(.serverUnreachable, detail: ns.localizedDescription)
        }
        if ns.domain == NSPOSIXErrorDomain && (ns.code == 61 || ns.code == 60) {
            return CompanionAPIError.failure(.portUnreachable, detail: ns.localizedDescription)
        }
        let classified = ConnectionFailureCode.classify(error)
        if classified != .unknown {
            return CompanionAPIError.failure(classified, detail: error.localizedDescription)
        }
        return CompanionAPIError.network(error)
    }

    /// True for short-lived network blips that are worth automatic retry.
    static func isTransient(_ error: Error) -> Bool {
        if let api = error as? CompanionAPIError {
            switch api {
            case .unreachable, .network: return true
            case .failure(let code, _):
                switch code {
                case .connectionTimeout, .serverUnreachable, .firewallOrNetworkBlock, .portUnreachable:
                    return true
                default:
                    return false
                }
            case .server(let msg):
                let low = msg.lowercased()
                return low.contains("timeout") || low.contains("timed out") || low.contains("connection reset")
            default: return false
            }
        }
        if let url = error as? URLError {
            switch url.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet,
                 .cannotConnectToHost, .dnsLookupFailed, .cannotFindHost,
                 .internationalRoamingOff, .dataNotAllowed, .secureConnectionFailed:
                return true
            default:
                return false
            }
        }
        let ns = error as NSError
        return ns.domain == NSPOSIXErrorDomain && (ns.code == 64 || ns.code == 57 || ns.code == 54)
    }

    /// Retry transient failures with short backoff (status, images, short RPC).
    func withTransientRetry<T>(
        attempts: Int = 3,
        baseDelayNanoseconds: UInt64 = 900_000_000,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0..<max(1, attempts) {
            do {
                return try await operation()
            } catch {
                let mapped = mapNetworkError(error)
                lastError = mapped
                guard Self.isTransient(mapped), attempt + 1 < attempts else { throw mapped }
                let delay = baseDelayNanoseconds * UInt64(attempt + 1)
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        throw lastError ?? CompanionAPIError.unreachable
    }
}
