import Foundation
import Network

/// Cleartext HTTP/1.1 over `NWConnection` for private NOCO hosts.
///
/// App Transport Security does **not** treat Tailscale CGNAT (`100.64.0.0/10`) as
/// “local networking”, so `URLSession` to `http://100.x.x.x` fails with ATS even when
/// TCP works. Network.framework is outside the URL Loading System → ATS does not apply.
///
/// Only used for Tailscale (and as ATS-fallback for pairable private hosts) — never for
/// arbitrary public internet hosts.
enum CompanionCleartextHTTP {
    struct Response {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
    }

    static func shouldBypassATS(for url: URL?) -> Bool {
        guard let host = url?.host, !host.isEmpty else { return false }
        return HostSanitizer.isTailscaleIP(host)
    }

    static func isATSError(_ error: Error) -> Bool {
        ConnectionFailureCode.classify(error) == .httpNotAllowedByATS
    }

    static func data(for request: URLRequest, timeout: TimeInterval? = nil) async throws -> (Data, HTTPURLResponse) {
        let url = try requireURL(request)
        let timeout = timeout ?? request.timeoutInterval
        let effectiveTimeout = timeout > 0 ? timeout : 45
        // NWError-96 / empty STREAM is common on Tailscale — retry with backoff, keep session.
        let delaysNs: [UInt64] = [280_000_000, 700_000_000, 1_400_000_000]
        var lastError: Error?
        for attempt in 0...delaysNs.count {
            do {
                let raw = try await perform(request: request, url: url, timeout: effectiveTimeout)
                let http = try makeHTTPURLResponse(url: url, status: raw.statusCode, headers: raw.headers, body: raw.body)
                if attempt > 0 {
                    logStreamRecovered(url: url, attempt: attempt, status: raw.statusCode)
                }
                return (raw.body, http)
            } catch {
                lastError = error
                let streamBlip = ConnectionFailureCode.isRemoteStreamInterrupted(error)
                    || ConnectionFailureCode.classify(error) == .remoteStreamInterrupted
                guard streamBlip, attempt < delaysNs.count else {
                    if streamBlip {
                        throw CompanionAPIError.failure(
                            .remoteStreamInterrupted,
                            detail: error.localizedDescription
                        )
                    }
                    throw error
                }
                let delay = delaysNs[attempt]
                logStreamInterrupted(
                    url: url,
                    request: request,
                    attempt: attempt + 1,
                    delayMs: Int(delay / 1_000_000),
                    error: error
                )
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        throw lastError ?? CompanionAPIError.failure(.remoteStreamInterrupted, detail: nil)
    }

    private static func logStreamInterrupted(
        url: URL,
        request: URLRequest,
        attempt: Int,
        delayMs: Int,
        error: Error
    ) {
        let host = url.host ?? "?"
        let port = url.port ?? 4747
        let path = url.path.isEmpty ? "/" : url.path
        let stamp = ISO8601DateFormatter().string(from: Date())
        Task { @MainActor in
            let d = ConnectionDiagnostics.shared
            d.log("REMOTE_STREAM_INTERRUPTED")
            d.log("Host: \(host)")
            d.log("Port: \(port)")
            d.log("Request: \(request.httpMethod ?? "GET") \(path)")
            d.log("Retry number: \(attempt)")
            d.log("Retry delay: \(delayMs) ms")
            d.log("timestamp: \(stamp)")
            d.log("Detail: \(error.localizedDescription)")
        }
    }

    private static func logStreamRecovered(url: URL, attempt: Int, status: Int) {
        Task { @MainActor in
            let d = ConnectionDiagnostics.shared
            d.log("REMOTE_STREAM recovered after retry \(attempt)")
            d.log("Host: \(url.host ?? "?")")
            d.log("HTTP after retry: \(status)")
        }
    }

    /// Streaming response as UTF-8 lines (SSE).
    static func lines(
        for request: URLRequest,
        timeout: TimeInterval? = nil
    ) async throws -> (lines: AsyncThrowingStream<String, Error>, response: HTTPURLResponse) {
        let url = try requireURL(request)
        let timeout = timeout ?? request.timeoutInterval
        let effectiveTimeout = timeout > 0 ? timeout : 600

        let host = url.host!
        let port = url.port ?? 4747
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            throw CompanionAPIError.invalidURL
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort,
            using: .tcp
        )
        try await connect(connection, timeout: min(effectiveTimeout, 15))

        let wire = try buildRequestData(request, url: url)
        try await send(wire, on: connection)

        // Read until headers complete.
        var buffer = Data()
        var status = 200
        var headers: [String: String] = [:]
        var headersReady = false
        let headerDeadline = Date().addingTimeInterval(min(effectiveTimeout, 30))
        while Date() < headerDeadline {
            let chunk = try await receive(on: connection, minimumIncompleteLength: 1, maximumLength: 64 * 1024)
            if chunk.isEmpty {
                connection.cancel()
                throw CompanionAPIError.failure(.noServerResponse, detail: "EOF before headers")
            }
            buffer.append(chunk)
            if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                let rest = buffer.subdata(in: range.upperBound..<buffer.endIndex)
                (status, headers) = try parseHeaderBlock(head)
                buffer = rest
                headersReady = true
                break
            }
        }
        guard headersReady else {
            connection.cancel()
            throw CompanionAPIError.failure(.connectionTimeout, detail: "cleartext header timeout")
        }

        let http = try makeHTTPURLResponse(url: url, status: status, headers: headers, body: Data())
        let primedBody = buffer

        let stream = AsyncThrowingStream<String, Error> { continuation in
            Task {
                var carry = primedBody
                do {
                    // Flush any lines already in the buffer after headers.
                    while let nl = carry.range(of: Data("\n".utf8)) {
                        var lineData = carry.subdata(in: carry.startIndex..<nl.lowerBound)
                        if lineData.last == UInt8(ascii: "\r") { lineData.removeLast() }
                        carry.removeSubrange(carry.startIndex..<nl.upperBound)
                        if let line = String(data: lineData, encoding: .utf8) {
                            continuation.yield(line)
                        }
                    }

                    while true {
                        let chunk = try await receive(
                            on: connection,
                            minimumIncompleteLength: 1,
                            maximumLength: 64 * 1024
                        )
                        if chunk.isEmpty { break }
                        carry.append(chunk)
                        while let nl = carry.range(of: Data("\n".utf8)) {
                            var lineData = carry.subdata(in: carry.startIndex..<nl.lowerBound)
                            if lineData.last == UInt8(ascii: "\r") { lineData.removeLast() }
                            carry.removeSubrange(carry.startIndex..<nl.upperBound)
                            if let line = String(data: lineData, encoding: .utf8) {
                                continuation.yield(line)
                            }
                        }
                    }
                    if !carry.isEmpty, let line = String(data: carry, encoding: .utf8) {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                connection.cancel()
            }
        }

        return (stream, http)
    }

    private static func requireURL(_ request: URLRequest) throws -> URL {
        guard let url = request.url, let host = url.host, !host.isEmpty else {
            throw CompanionAPIError.invalidURL
        }
        // Safety: never cleartext-bypass to public internet.
        let h = HostSanitizer.hostOnly(host)
        guard HostSanitizer.isTailscaleIP(h) || HostSanitizer.isPrivateLanIP(h) else {
            throw CompanionAPIError.failure(
                .invalidRemoteHost,
                detail: "Cleartext transport only for LAN/Tailscale"
            )
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
                throw CompanionAPIError.failure(.connectionTimeout, detail: "cleartext HTTP timeout")
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
        let port = url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 4747)
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            throw CompanionAPIError.invalidURL
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort,
            using: .tcp
        )

        try await connect(connection, timeout: min(timeout, 15))
        defer { connection.cancel() }

        let wire = try buildRequestData(request, url: url)
        try await send(wire, on: connection)

        var buffer = Data()
        // Read until we have headers + full body (Content-Length) or connection end.
        while true {
            let chunk = try await receive(on: connection, minimumIncompleteLength: 1, maximumLength: 64 * 1024)
            if chunk.isEmpty { break }
            buffer.append(chunk)
            if let parsed = try parseCompleteHTTPMessage(buffer) {
                return parsed
            }
            // Cap memory for runaway responses
            if buffer.count > 12 * 1024 * 1024 {
                throw CompanionAPIError.failure(.noServerResponse, detail: "response too large")
            }
        }
        if let parsed = try parseCompleteHTTPMessage(buffer, allowEOF: true) {
            return parsed
        }
        throw CompanionAPIError.failure(.noServerResponse, detail: "incomplete HTTP response")
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
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(nil)
                case .failed(let err):
                    finish(err)
                case .cancelled:
                    finish(CompanionAPIError.failure(.firewallOrNetworkBlock, detail: "cancelled"))
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue.global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(CompanionAPIError.failure(.connectionTimeout, detail: "TCP connect timeout"))
            }
        }
    }

    private static func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            })
        }
    }

    private static func receive(
        on connection: NWConnection,
        minimumIncompleteLength: Int,
        maximumLength: Int
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            connection.receive(
                minimumIncompleteLength: minimumIncompleteLength,
                maximumLength: maximumLength
            ) { content, _, isComplete, error in
                if let error {
                    if ConnectionFailureCode.isRemoteStreamInterrupted(error) {
                        cont.resume(throwing: CompanionAPIError.failure(
                            .remoteStreamInterrupted,
                            detail: error.localizedDescription
                        ))
                    } else {
                        cont.resume(throwing: error)
                    }
                    return
                }
                if let content {
                    cont.resume(returning: content)
                } else if isComplete {
                    cont.resume(returning: Data())
                } else {
                    cont.resume(returning: Data())
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
            "User-Agent: NOCOAI-iOS-Cleartext/1"
        ]

        if let headers = request.allHTTPHeaderFields {
            for (key, value) in headers {
                if key.lowercased() == "host" { continue }
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

        var message = headerLines.joined(separator: "\r\n") + "\r\n\r\n"
        var data = Data(message.utf8)
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
        // No content-length: wait for connection close (caller passes allowEOF on EOF).
        return nil
    }

    private static func parseHeaderBlock(_ head: Data) throws -> (Int, [String: String]) {
        guard let text = String(data: head, encoding: .utf8) else {
            throw CompanionAPIError.failure(.noServerResponse, detail: "bad header encoding")
        }
        let lines = text.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else {
            throw CompanionAPIError.failure(.noServerResponse, detail: "empty headers")
        }
        let parts = statusLine.split(separator: " ")
        guard parts.count >= 2, let code = Int(parts[1]) else {
            throw CompanionAPIError.failure(.noServerResponse, detail: "bad status line")
        }
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
        headers: [String: String],
        body: Data
    ) throws -> HTTPURLResponse {
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            throw CompanionAPIError.failure(.noServerResponse, detail: "HTTPURLResponse failed")
        }
        _ = body
        return response
    }
}
