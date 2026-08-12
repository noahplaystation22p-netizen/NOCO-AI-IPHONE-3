import Foundation
import Network

/// Precise connection failure codes — never collapse everything to “HTTP blocked”.
enum ConnectionFailureCode: String, Codable, Equatable {
    case ok = "OK"
    case httpNotAllowedByATS = "HTTP_NOT_ALLOWED_BY_ATS"
    case serverUnreachable = "SERVER_UNREACHABLE"
    case connectionTimeout = "CONNECTION_TIMEOUT"
    case portUnreachable = "PORT_UNREACHABLE"
    case tailscaleUnavailable = "TAILSCALE_UNAVAILABLE"
    case firewallOrNetworkBlock = "FIREWALL_OR_NETWORK_BLOCK"
    case httpError4xx = "HTTP_ERROR_4XX"
    case httpError5xx = "HTTP_ERROR_5XX"
    case httpError401 = "HTTP_ERROR_401"
    case httpError403 = "HTTP_ERROR_403"
    case httpError404 = "HTTP_ERROR_404"
    case invalidRemoteHost = "INVALID_REMOTE_HOST"
    case noServerResponse = "NO_SERVER_RESPONSE"
    case tlsError = "TLS_ERROR"
    case remoteAccessDisabled = "REMOTE_ACCESS_DISABLED"
    case dnsFailure = "DNS_FAILURE"
    case offline = "NO_CONNECTION"
    case remoteStreamInterrupted = "REMOTE_STREAM_INTERRUPTED"
    case unknown = "UNKNOWN"

    var userMessage: String {
        switch self {
        case .ok:
            return "Verbindung OK"
        case .httpNotAllowedByATS:
            return "NOCO ist gerade nicht erreichbar. Bitte neuestes NOCO-IPA installieren."
        case .serverUnreachable:
            return "NOCO ist gerade nicht erreichbar. WLAN/Tailscale und PC prüfen."
        case .connectionTimeout:
            return "Verbindung wird wiederhergestellt…"
        case .portUnreachable:
            return "NOCO ist gerade nicht erreichbar. Läuft der PC-Server?"
        case .tailscaleUnavailable:
            return "NOCO ist offline. Tailscale am iPhone und PC prüfen."
        case .firewallOrNetworkBlock:
            return "NOCO ist gerade nicht erreichbar."
        case .httpError4xx:
            return "NOCO hat die Anfrage abgelehnt."
        case .httpError5xx:
            return "NOCO hat einen Serverfehler. PC neu starten."
        case .httpError401:
            return "Bitte erneut koppeln."
        case .httpError403:
            return "Zugriff verweigert. Remote am PC prüfen."
        case .httpError404:
            return "NOCO am PC aktualisieren."
        case .invalidRemoteHost:
            return "Ungültige Adresse — nur die IP eingeben."
        case .noServerResponse:
            return "Verbindung wird wiederhergestellt…"
        case .tlsError:
            return "NOCO ist gerade nicht erreichbar."
        case .remoteAccessDisabled:
            return "Remote-Zugriff ist auf dem NOCO-PC deaktiviert."
        case .dnsFailure:
            return "NOCO ist gerade nicht erreichbar."
        case .offline:
            return "NOCO ist offline."
        case .remoteStreamInterrupted:
            return "Verbindung wird wiederhergestellt…"
        case .unknown:
            return "NOCO ist gerade nicht erreichbar."
        }
    }

    /// Short-lived blip — keep session/host; retry instead of full reconnect.
    var isSoftTransient: Bool {
        switch self {
        case .remoteStreamInterrupted, .connectionTimeout, .noServerResponse:
            return true
        default:
            return false
        }
    }

    static func from(httpStatus: Int) -> ConnectionFailureCode {
        switch httpStatus {
        case 200...299: return .ok
        case 401: return .httpError401
        case 403: return .httpError403
        case 404: return .httpError404
        case 400...499: return .httpError4xx
        case 500...599: return .httpError5xx
        default: return .unknown
        }
    }

    static func classify(_ error: Error) -> ConnectionFailureCode {
        if let api = error as? CompanionAPIError {
            return api.failureCode
        }
        if let url = error as? URLError {
            return from(urlError: url)
        }
        let ns = error as NSError
        if isRemoteStreamInterrupted(ns) {
            return .remoteStreamInterrupted
        }
        if ns.domain == NSPOSIXErrorDomain {
            switch ns.code {
            case 61, 60: return .portUnreachable // ECONNREFUSED / ETIMEDOUT
            case 64, 65: return .serverUnreachable
            case 51, 50: return .firewallOrNetworkBlock
            case 96: return .remoteStreamInterrupted // ENODATA / STREAM empty
            default: break
            }
        }
        let low = error.localizedDescription.lowercased()
        if low.contains("app transport security") || low.contains("secure connection required") {
            return .httpNotAllowedByATS
        }
        if low.contains("timeout") || low.contains("timed out") {
            return .connectionTimeout
        }
        if low.contains("no message available on stream")
            || (low.contains("nwerror") && low.contains("96")) {
            return .remoteStreamInterrupted
        }
        return .unknown
    }

    /// Network.NWError 96 / POSIX ENODATA — common on Tailscale cleartext short streams.
    static func isRemoteStreamInterrupted(_ error: Error) -> Bool {
        isRemoteStreamInterrupted(error as NSError)
    }

    static func isRemoteStreamInterrupted(_ ns: NSError) -> Bool {
        if ns.code == 96 {
            let domain = ns.domain.lowercased()
            if domain.contains("network") || domain == NSPOSIXErrorDomain.lowercased() {
                return true
            }
        }
        let low = ns.localizedDescription.lowercased()
        return low.contains("no message available on stream")
            || (low.contains("nwerror") && low.contains("96"))
            || (low.contains("fehler 96") && low.contains("stream"))
    }

    static func from(urlError: URLError) -> ConnectionFailureCode {
        switch urlError.code {
        case .appTransportSecurityRequiresSecureConnection:
            return .httpNotAllowedByATS
        case .timedOut:
            return .connectionTimeout
        case .cannotConnectToHost:
            return .portUnreachable
        case .networkConnectionLost, .notConnectedToInternet:
            return .firewallOrNetworkBlock
        case .cannotFindHost, .dnsLookupFailed:
            return .dnsFailure
        case .secureConnectionFailed, .serverCertificateUntrusted,
             .clientCertificateRejected:
            return .tlsError
        case .badURL:
            return .invalidRemoteHost
        default:
            let low = urlError.localizedDescription.lowercased()
            if low.contains("app transport") || low.contains("secure connection required") {
                return .httpNotAllowedByATS
            }
            return .unknown
        }
    }
}

struct ConnectionProbeSnapshot: Equatable {
    var pathKind: String = "—"
    var activeHost: String = ""
    var port: Int = 4747
    var localHost: String = ""
    var remoteHost: String = ""
    var localReachable: Bool?
    var remoteReachable: Bool?
    var tailscaleDetected: Bool = false
    var tcpOK: Bool?
    var httpStatus: Int?
    var httpLabel: String = "—"
    var serverReachable: Bool?
    var responseMs: Int?
    var failureCode: ConnectionFailureCode = .unknown
    var summary: String = ""
    var connectingInProgress: Bool = false
}

/// Live connection diagnostics + step-by-step remote/local probes.
@MainActor
final class ConnectionDiagnostics: ObservableObject {
    static let shared = ConnectionDiagnostics()

    @Published private(set) var logLines: [String] = []
    @Published private(set) var snapshot = ConnectionProbeSnapshot()
    @Published private(set) var isRunning = false
    @Published private(set) var lastExport = ""

    private let maxLines = 400
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private init() {}

    func clearLog() {
        logLines = []
    }

    func log(_ message: String) {
        let line = "[\(timeFormatter.string(from: Date()))] \(sanitize(message))"
        logLines.append(line)
        if logLines.count > maxLines {
            logLines.removeFirst(logLines.count - maxLines)
        }
    }

    /// Strip secrets from free-form messages.
    private func sanitize(_ message: String) -> String {
        var s = message
        // Redact bearer-looking tokens and long hex/base64 blobs.
        s = s.replacingOccurrences(
            of: #"(?i)(bearer\s+)[a-z0-9\-._~+/]+=*"#,
            with: "$1***",
            options: .regularExpression
        )
        s = s.replacingOccurrences(
            of: #"(?i)(token[\"'\s:=]+)[a-z0-9\-._~+/]{12,}"#,
            with: "$1***",
            options: .regularExpression
        )
        return s
    }

    func exportText(appVersion: String, connection: ConnectionStore) -> String {
        let snap = snapshot
        let body = """
        NOCO Connection Diagnostics

        App Version: \(appVersion)
        Timestamp: \(ISO8601DateFormatter().string(from: Date()))
        Connection Mode: \(connection.activePath == .remote ? "Remote" : "Local")
        Online: \(connection.isOnline ? "YES" : "NO")
        Active Host: \(connection.serverHost):\(connection.serverPort)
        Local Host: \(connection.localHost.isEmpty ? "—" : connection.localHost)
        Tailscale Host: \(connection.remoteHost.isEmpty ? "—" : connection.remoteHost)

        Tailscale: \(snap.tailscaleDetected ? "AVAILABLE" : "NOT_DETECTED")
        Local Reachable: \(boolLabel(snap.localReachable))
        Remote Reachable: \(boolLabel(snap.remoteReachable))
        TCP: \(boolLabel(snap.tcpOK, yes: "CONNECTED", no: "FAILED"))
        HTTP: \(snap.httpLabel)
        Server: \(boolLabel(snap.serverReachable, yes: "REACHABLE", no: "UNREACHABLE"))
        Response Time: \(snap.responseMs.map { "\($0) ms" } ?? "—")
        Error: \(snap.failureCode.rawValue)
        Summary: \(snap.summary)

        --- Live Knowledge ---
        Web: \(lkBool(connection.status.liveKnowledge?.webAvailable))
        Search: \(lkBool(connection.status.liveKnowledge?.searchAvailable))
        Last Search: \(connection.status.liveKnowledge?.lastSearchAt ?? "—")
        Last Latency: \(connection.status.liveKnowledge?.lastLatencyMs.map { "\(Int($0)) ms" } ?? "—")
        Provider: \(connection.status.liveKnowledge?.provider ?? "—")
        Cache: \(connection.status.liveKnowledge?.cacheEntries.map(String.init) ?? "—")
        Last Reason: \(connection.status.liveKnowledge?.lastReason ?? "—")

        --- Live Log ---
        \(logLines.joined(separator: "\n"))
        """
        lastExport = body
        return body
    }

    private func lkBool(_ value: Bool?) -> String {
        guard let value else { return "Unknown" }
        return value ? "Available" : "Unavailable"
    }

    private func boolLabel(_ value: Bool?, yes: String = "YES", no: String = "NO") -> String {
        guard let value else { return "—" }
        return value ? yes : no
    }

    /// Full pipeline used by Diagnose UI and automatic remote-failure analysis.
    func runFullProbe(connection: ConnectionStore) async {
        guard !isRunning else { return }
        isRunning = true
        snapshot.connectingInProgress = true
        defer {
            isRunning = false
            snapshot.connectingInProgress = false
        }

        log("Connection Manager gestartet")
        let port = connection.serverPort
        let local = HostSanitizer.hostOnly(connection.localHost)
        let remote = HostSanitizer.hostOnly(connection.remoteHost)
        let active = HostSanitizer.hostOnly(connection.serverHost)
        // Sticky remote session: confirm Tailscale first (avoid LAN timeout spam).
        let remoteFirst = connection.activePath == .remote

        snapshot.port = port
        snapshot.localHost = local
        snapshot.remoteHost = remote
        snapshot.activeHost = active.isEmpty ? (local.isEmpty ? remote : local) : active
        snapshot.pathKind = connection.activePath == .remote ? "TAILSCALE" : "LOCAL"
        snapshot.tailscaleDetected = HostSanitizer.isTailscaleIP(remote) || HostSanitizer.isTailscaleIP(active)
        snapshot.failureCode = .unknown
        snapshot.summary = ""
        snapshot.tcpOK = nil
        snapshot.httpStatus = nil
        snapshot.httpLabel = "—"
        snapshot.serverReachable = nil
        snapshot.responseMs = nil
        snapshot.localReachable = nil
        snapshot.remoteReachable = nil

        if active.isEmpty && local.isEmpty && remote.isEmpty {
            snapshot.failureCode = .invalidRemoteHost
            snapshot.summary = ConnectionFailureCode.invalidRemoteHost.userMessage
            log("Error: INVALID_REMOTE_HOST")
            return
        }

        var failedRemote: HostProbeResult?

        if remoteFirst, !remote.isEmpty {
            if HostSanitizer.isTailscaleIP(remote) {
                log("Tailscale detected")
                snapshot.tailscaleDetected = true
            }
            log("Tailscale IP: \(remote)")
            log("Remote Host: \(remote):\(port)")
            let remoteResult = await probeHost(remote, port: port, label: "Tailscale")
            snapshot.remoteReachable = remoteResult.serverOK
            if remoteResult.serverOK {
                applySuccess(remoteResult, path: "TAILSCALE", host: remote)
                snapshot.summary = "Tailscale Remote Connected."
                snapshot.failureCode = .ok
                if !local.isEmpty {
                    log("Local Host: \(local):\(port) (check only)")
                    let localResult = await probeHost(local, port: port, label: "Local")
                    snapshot.localReachable = localResult.serverOK
                } else {
                    snapshot.localReachable = false
                }
                return
            }
            log("Remote Connection: FAILED (\(remoteResult.code.rawValue))")
            failedRemote = remoteResult
        }

        if !local.isEmpty {
            log("Local Host: \(local):\(port)")
            let localResult = await probeHost(local, port: port, label: "Local")
            snapshot.localReachable = localResult.serverOK
            if localResult.serverOK {
                applySuccess(localResult, path: "LOCAL", host: local)
                log("Local Connection: OK")
                if !remote.isEmpty, !remoteFirst {
                    log("Tailscale IP: \(remote)")
                    let remoteCheck = await probeHost(remote, port: port, label: "Tailscale")
                    snapshot.remoteReachable = remoteCheck.serverOK
                    snapshot.tailscaleDetected = true
                }
                snapshot.summary = "Local Connected — schnellste Verbindung aktiv."
                snapshot.failureCode = .ok
                snapshot.pathKind = "LOCAL"
                return
            }
            log("Local Connection: FAILED (\(localResult.code.rawValue))")
        } else {
            log("Local Host: —")
            log("Local Connection: SKIPPED")
        }

        if let failedRemote {
            applyFailure(failedRemote, host: remote, port: port)
            return
        }

        if !remote.isEmpty {
            if HostSanitizer.isTailscaleIP(remote) {
                log("Tailscale detected")
                snapshot.tailscaleDetected = true
            } else {
                log("Remote Host is not a Tailscale CGNAT IP")
            }
            log("Tailscale IP: \(remote)")
            log("Remote Host: \(remote):\(port)")
            let remoteResult = await probeHost(remote, port: port, label: "Tailscale")
            snapshot.remoteReachable = remoteResult.serverOK
            if remoteResult.serverOK {
                applySuccess(remoteResult, path: "TAILSCALE", host: remote)
                snapshot.summary = "Tailscale Remote Connected."
                snapshot.failureCode = .ok
                return
            }
            applyFailure(remoteResult, host: remote, port: port)
            return
        }

        // Active host fallback (paired but hosts not split yet)
        if !active.isEmpty {
            log("Active Host probe: \(active):\(port)")
            let result = await probeHost(active, port: port, label: "Active")
            if result.serverOK {
                applySuccess(result, path: HostSanitizer.isTailscaleIP(active) ? "TAILSCALE" : "LOCAL", host: active)
                snapshot.failureCode = .ok
                snapshot.summary = "Server erreichbar."
            } else {
                if HostSanitizer.isTailscaleIP(active) || snapshot.tailscaleDetected {
                    var adjusted = result
                    if result.code == .portUnreachable || result.code == .connectionTimeout {
                        if result.code == .connectionTimeout {
                            adjusted.code = .tailscaleUnavailable
                        }
                    }
                    applyFailure(adjusted, host: active, port: port)
                } else {
                    applyFailure(result, host: active, port: port)
                }
            }
            return
        }

        snapshot.failureCode = .tailscaleUnavailable
        snapshot.summary = ConnectionFailureCode.tailscaleUnavailable.userMessage
        log("Error: TAILSCALE_UNAVAILABLE")
    }

    private func applySuccess(_ result: HostProbeResult, path: String, host: String) {
        snapshot.pathKind = path
        snapshot.activeHost = host
        snapshot.tcpOK = result.tcpOK
        snapshot.httpStatus = result.httpStatus
        snapshot.httpLabel = result.httpLabel
        snapshot.serverReachable = true
        snapshot.responseMs = result.responseMs
        snapshot.failureCode = .ok
        log(path == "LOCAL" ? "Local connection established" : "Remote connection established")
    }

    private func applyFailure(_ result: HostProbeResult, host: String, port: Int) {
        snapshot.activeHost = host
        snapshot.tcpOK = result.tcpOK
        snapshot.httpStatus = result.httpStatus
        snapshot.httpLabel = result.httpLabel
        snapshot.serverReachable = false
        snapshot.responseMs = result.responseMs
        snapshot.failureCode = result.code
        snapshot.summary = humanSummary(result: result, host: host, port: port)
        log("HTTP ERROR")
        log("Error: \(result.code.rawValue)")
        log("Host: \(host)")
        log("Port: \(port)")
        if let detail = result.detail, !detail.isEmpty {
            log("Detail: \(detail)")
        }
    }

    private func humanSummary(result: HostProbeResult, host: String, port: Int) -> String {
        switch result.code {
        case .httpNotAllowedByATS:
            return "Der Server ist ggf. erreichbar, aber iOS blockiert die HTTP-Verbindung (ATS)."
        case .tailscaleUnavailable:
            return "Tailscale ist nicht aktiv oder \(host) antwortet nicht über Tailscale."
        case .portUnreachable:
            return "Tailscale/Netz ok-ish, aber der NOCO-Server antwortet nicht auf Port \(port)."
        case .connectionTimeout:
            return "Keine Antwort von \(host):\(port) — Firewall, Server aus, oder Tailscale getrennt."
        case .firewallOrNetworkBlock:
            return "Netzwerk blockiert TCP zu \(host):\(port) (Firewall oder kein Pfad)."
        case .tlsError:
            return "TLS/HTTPS-Fehler — bitte nur die IP ohne https:// verwenden."
        case .remoteAccessDisabled:
            return "PC erreichbar, aber Remote-Zugriff ist deaktiviert."
        default:
            return result.code.userMessage
        }
    }

    private struct HostProbeResult {
        var tcpOK: Bool
        var httpStatus: Int?
        var httpLabel: String
        var serverOK: Bool
        var responseMs: Int?
        var code: ConnectionFailureCode
        var detail: String?
    }

    private func probeHost(_ host: String, port: Int, label: String) async -> HostProbeResult {
        let cleaned = HostSanitizer.hostOnly(host)
        guard HostSanitizer.isPairableHost(cleaned) || HostSanitizer.isPrivateLanIP(cleaned) || HostSanitizer.isTailscaleIP(cleaned) else {
            log("\(label): INVALID_REMOTE_HOST (\(cleaned))")
            return HostProbeResult(
                tcpOK: false,
                httpStatus: nil,
                httpLabel: "INVALID",
                serverOK: false,
                responseMs: nil,
                code: .invalidRemoteHost,
                detail: cleaned
            )
        }

        log("TCP connection started → \(cleaned):\(port)")
        let tcp = await Self.tcpConnect(host: cleaned, port: port, timeout: HostSanitizer.isTailscaleIP(cleaned) ? 8 : 2.5)
        if tcp {
            log("TCP connection successful")
        } else {
            log("TCP connection failed")
        }

        log("HTTP request started → /api/v1/ping")
        if HostSanitizer.isTailscaleIP(cleaned) {
            log("HTTP transport: cleartext NW (Tailscale / ATS bypass)")
        }
        let started = Date()
        let http = await Self.httpPing(host: cleaned, port: port, timeout: HostSanitizer.isTailscaleIP(cleaned) ? 10 : 3)
        let ms = Int(Date().timeIntervalSince(started) * 1000)

        if let status = http.status {
            log("HTTP response: \(status)")
        } else if let code = http.code {
            log("HTTP ERROR (\(code.rawValue))")
        } else {
            log("HTTP ERROR (no response)")
        }

        if http.ok {
            return HostProbeResult(
                tcpOK: tcp || true,
                httpStatus: http.status,
                httpLabel: http.status.map { "\($0) OK" } ?? "OK",
                serverOK: true,
                responseMs: ms,
                code: .ok,
                detail: nil
            )
        }

        var code = http.code ?? (tcp ? .noServerResponse : .portUnreachable)
        // TCP ok + ATS → clear ATS diagnosis
        if code == .httpNotAllowedByATS {
            // keep
        } else if !tcp && (code == .unknown || code == .serverUnreachable) {
            code = .firewallOrNetworkBlock
        } else if tcp && http.status == nil && code == .connectionTimeout {
            code = .connectionTimeout
        }

        let labelText: String
        if let status = http.status {
            labelText = "\(status)"
        } else if code == .httpNotAllowedByATS {
            labelText = "Blocked (ATS)"
        } else if code == .connectionTimeout {
            labelText = "Timeout"
        } else {
            labelText = "Failed"
        }

        return HostProbeResult(
            tcpOK: tcp,
            httpStatus: http.status,
            httpLabel: labelText,
            serverOK: false,
            responseMs: ms,
            code: code,
            detail: http.detail
        )
    }

    private static func tcpConnect(host: String, port: Int, timeout: TimeInterval) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return false }
        return await withCheckedContinuation { cont in
            let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            let lock = NSLock()
            var resumed = false
            func finish(_ ok: Bool) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                conn.cancel()
                cont.resume(returning: ok)
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(true)
                case .failed, .cancelled:
                    finish(false)
                default:
                    break
                }
            }
            conn.start(queue: DispatchQueue.global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(false)
            }
        }
    }

    private struct HTTPPingOutcome {
        var ok: Bool
        var status: Int?
        var code: ConnectionFailureCode?
        var detail: String?
    }

    private static func httpPing(host: String, port: Int, timeout: TimeInterval) async -> HTTPPingOutcome {
        let urlString = "http://\(host):\(port)/api/v1/ping"
        guard let url = URL(string: urlString) else {
            return HTTPPingOutcome(ok: false, status: nil, code: .invalidRemoteHost, detail: urlString)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let data: Data
            let response: URLResponse
            if CompanionCleartextHTTP.shouldBypassATS(for: url) {
                // Tailscale CGNAT is outside ATS “local networking” — use NW cleartext.
                let (body, http) = try await CompanionCleartextHTTP.data(for: request, timeout: timeout)
                data = body
                response = http
            } else {
                do {
                    (data, response) = try await URLSession.shared.data(for: request)
                } catch {
                    if CompanionCleartextHTTP.isATSError(error),
                       HostSanitizer.isTailscaleIP(host) || HostSanitizer.isPrivateLanIP(host) {
                        let (body, http) = try await CompanionCleartextHTTP.data(for: request, timeout: timeout)
                        data = body
                        response = http
                    } else {
                        throw error
                    }
                }
            }
            guard let http = response as? HTTPURLResponse else {
                return HTTPPingOutcome(ok: false, status: nil, code: .noServerResponse, detail: nil)
            }
            if (200...299).contains(http.statusCode) {
                // Soft-check body if present
                if let ping = try? JSONDecoder().decode(PingResponse.self, from: data), ping.isAlive == false {
                    return HTTPPingOutcome(ok: false, status: http.statusCode, code: .noServerResponse, detail: "ping not alive")
                }
                return HTTPPingOutcome(ok: true, status: http.statusCode, code: .ok, detail: nil)
            }
            return HTTPPingOutcome(
                ok: false,
                status: http.statusCode,
                code: ConnectionFailureCode.from(httpStatus: http.statusCode),
                detail: nil
            )
        } catch {
            let code = ConnectionFailureCode.classify(error)
            return HTTPPingOutcome(ok: false, status: nil, code: code, detail: error.localizedDescription)
        }
    }
}
