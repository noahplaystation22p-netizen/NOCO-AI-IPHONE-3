import Foundation
import Network

/// Cleartext HTTP/1.1 over `NWConnection` for Tailscale CGNAT hosts.
/// Shared by main app keyboard extension — ATS does not apply to Network.framework.
enum NOCOCleartextHTTP {
    struct Response {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
    }

    enum TransportError: LocalizedError {
        case badURL
        case notPrivateHost
        case timeout
        case streamInterrupted(String)
        case incomplete
        case cancelled

        var errorDescription: String? {
            switch self {
            case .badURL: return "Ungültige Adresse"
            case .notPrivateHost: return "Cleartext nur für LAN/Tailscale"
            case .timeout: return "Zeitüberschreitung"
            case .streamInterrupted: return "Stream unterbrochen"
            case .incomplete: return "Unvollständige Antwort"
            case .cancelled: return "Abgebrochen"
            }
        }
    }

    static func shouldUseCleartext(for url: URL?) -> Bool {
        guard let host = url?.host, !host.isEmpty else { return false }
        // Tailscale always; private LAN also uses NW when URLSession/ATS is flaky in extensions.
        return isTailscaleIP(host)
    }

    /// Prefer cleartext for any private mesh host (keyboard + Tailscale).
    static func shouldPreferCleartext(for url: URL?) -> Bool {
        guard let host = url?.host, !host.isEmpty else { return false }
        return isTailscaleIP(host) || isPrivateLanIP(host)
    }

    static func isTailscaleIP(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 100 && parts[1] >= 64 && parts[1] <= 127
    }

    static func isPrivateLanIP(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        if parts[0] == 10 { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        return false
    }

    static func data(for request: URLRequest, timeout: TimeInterval? = nil) async throws -> (Data, HTTPURLResponse) {
        let url = try requireURL(request)
        let timeout = timeout ?? request.timeoutInterval
        let effectiveTimeout = timeout > 0 ? timeout : 18
        let delaysNs: [UInt64] = [280_000_000, 700_000_000, 1_200_000_000]
        var lastError: Error?
        for attempt in 0...delaysNs.count {
            do {
                let raw = try await perform(request: request, url: url, timeout: effectiveTimeout)
                let http = try makeHTTPURLResponse(url: url, status: raw.statusCode, headers: raw.headers)
                return (raw.body, http)
            } catch {
                lastError = error
                guard isStreamInterrupted(error), attempt < delaysNs.count else { throw error }
                try? await Task.sleep(nanoseconds: delaysNs[attempt])
            }
        }
        throw lastError ?? TransportError.streamInterrupted("retry exhausted")
    }

    private static func isStreamInterrupted(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.code == 96 {
            let domain = ns.domain.lowercased()
            if domain.contains("network") || domain == NSPOSIXErrorDomain.lowercased() {
                return true
            }
        }
        if case TransportError.streamInterrupted = error { return true }
        let low = ns.localizedDescription.lowercased()
        return low.contains("no message available on stream")
            || (low.contains("nwerror") && low.contains("96"))
    }

    private static func requireURL(_ request: URLRequest) throws -> URL {
        guard let url = request.url, let host = url.host, !host.isEmpty else {
            throw TransportError.badURL
        }
        guard isTailscaleIP(host) || isPrivateLanIP(host) else {
            throw TransportError.notPrivateHost
        }
        return url
    }

    private static func perform(
        request: URLRequest,
        url: URL,
        timeout: TimeInterval
    ) async throws -> Response {
        try await withThrowingTaskGroup(of: Response.self) { group in
            group.addTask {
                try await self.sendAndReceive(request: request, url: url, timeout: timeout)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw TransportError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private static func sendAndReceive(
        request: URLRequest,
        url: URL,
        timeout: TimeInterval
    ) async throws -> Response {
        let host = url.host!
        let port = url.port ?? 4747
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            throw TransportError.badURL
        }
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort,
            using: .tcp
        )
        try await connect(connection, timeout: min(timeout, 12))
        defer { connection.cancel() }

        let wire = try buildRequestData(request, url: url)
        try await send(wire, on: connection)

        var buffer = Data()
        while true {
            let chunk = try await receive(on: connection)
            if chunk.isEmpty { break }
            buffer.append(chunk)
            if let parsed = try parseCompleteHTTPMessage(buffer) {
                return parsed
            }
            if buffer.count > 4 * 1024 * 1024 {
                throw TransportError.incomplete
            }
        }
        if let parsed = try parseCompleteHTTPMessage(buffer, allowEOF: true) {
            return parsed
        }
        throw TransportError.incomplete
    }

    private static func connect(_ connection: NWConnection, timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let lock = NSLock()
            var resumed = false
            func finish(_ error: Error?) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(nil)
                case .failed(let err): finish(err)
                case .cancelled: finish(TransportError.cancelled)
                default: break
                }
            }
            connection.start(queue: DispatchQueue.global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(TransportError.timeout)
            }
        }
    }

    private static func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            })
        }
    }

    private static func receive(on connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { content, _, isComplete, error in
                if let error {
                    if isStreamInterrupted(error) {
                        cont.resume(throwing: TransportError.streamInterrupted(error.localizedDescription))
                    } else {
                        cont.resume(throwing: error)
                    }
                    return
                }
                if let content {
                    cont.resume(returning: content)
                } else {
                    cont.resume(returning: Data())
                    _ = isComplete
                }
            }
        }
    }

    private static func buildRequestData(_ request: URLRequest, url: URL) throws -> Data {
        let method = (request.httpMethod ?? "GET").uppercased()
        var path = url.path
        if path.isEmpty { path = "/" }
        if let query = url.query, !query.isEmpty {
            path += "?\(query)"
        }
        let host = url.host!
        let port = url.port
        let hostHeader: String
        if let port, port != 80, port != 443 {
            hostHeader = "\(host):\(port)"
        } else {
            hostHeader = host
        }
        var headerLines: [String] = [
            "\(method) \(path) HTTP/1.1",
            "Host: \(hostHeader)",
            "Connection: close",
            "Accept: */*",
            "User-Agent: NOCOAI-Keyboard-Cleartext/1"
        ]
        if let headers = request.allHTTPHeaderFields {
            for (key, value) in headers where key.lowercased() != "host" {
                headerLines.append("\(key): \(value)")
            }
        }
        let body = request.httpBody ?? Data()
        let hasContentLength = request.allHTTPHeaderFields?.keys.contains(where: {
            $0.lowercased() == "content-length"
        }) == true
        if !hasContentLength {
            headerLines.append("Content-Length: \(body.count)")
        }
        var data = Data((headerLines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        data.append(body)
        return data
    }

    private static func parseCompleteHTTPMessage(_ buffer: Data, allowEOF: Bool = false) throws -> Response? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = buffer.subdata(in: buffer.startIndex..<headerEnd.lowerBound)
        let bodyStart = headerEnd.upperBound
        let (status, headers) = try parseHeaderBlock(head)
        let lower = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        if let lenStr = lower["content-length"], let len = Int(lenStr) {
            let available = buffer.count - bodyStart
            if available < len { return nil }
            let body = buffer.subdata(in: bodyStart..<(bodyStart + len))
            return Response(statusCode: status, headers: headers, body: body)
        }
        if allowEOF {
            let body = buffer.subdata(in: bodyStart..<buffer.endIndex)
            return Response(statusCode: status, headers: headers, body: body)
        }
        return nil
    }

    private static func parseHeaderBlock(_ head: Data) throws -> (Int, [String: String]) {
        guard let text = String(data: head, encoding: .utf8) else {
            throw TransportError.incomplete
        }
        let lines = text.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else { throw TransportError.incomplete }
        let parts = statusLine.split(separator: " ")
        guard parts.count >= 2, let code = Int(parts[1]) else { throw TransportError.incomplete }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        return (code, headers)
    }

    private static func makeHTTPURLResponse(
        url: URL,
        status: Int,
        headers: [String: String]
    ) throws -> HTTPURLResponse {
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            throw TransportError.incomplete
        }
        return response
    }
}
