import Foundation
import WatchConnectivity
import os

/// Watch-side WatchConnectivity client — all AI goes through iPhone.
@MainActor
final class WatchSessionClient: NSObject, ObservableObject {
    static let shared = WatchSessionClient()

    @Published private(set) var snapshot: WatchStatusSnapshot = .offline
    @Published private(set) var phoneReachable = false
    @Published private(set) var isActivated = false
    @Published private(set) var watchPhoneLink: WatchLinkState = .offline
    @Published private(set) var diagnosticLines: [String] = []

    private var session: WCSession?
    private var pending: [String: CheckedContinuation<Result<String, WatchClientError>, Never>] = [:]
    private var activeRequestId: String?
    private var inFlightAsk = false
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var lastReachableAt = Date()
    private let log = Logger(subsystem: "de.noco.nocoai.watch", category: "Session")

    enum WatchClientError: LocalizedError {
        case notReachable
        case emptyReply
        case server(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .notReachable: return WatchUserFacingError.phoneAway
            case .emptyReply: return WatchUserFacingError.empty
            case .server(let m): return WatchUserFacingError.sanitize(m)
            case .cancelled: return nil
            }
        }
    }

    func activate() {
        guard WCSession.isSupported() else {
            watchPhoneLink = .offline
            appendDiag("WatchConnectivity unsupported")
            return
        }
        if session == nil {
            let s = WCSession.default
            s.delegate = self
            session = s
        }
        watchPhoneLink = .connecting
        appendDiag("Watch session activating")
        session?.activate()
    }

    func refreshStatus() {
        guard let session, session.activationState == .activated else {
            softReconnectIfNeeded()
            return
        }
        phoneReachable = session.isReachable
        updateWatchPhoneLink(reachable: session.isReachable, activated: true)

        let msg = WatchBridgeMessage(action: .statusRequest)
        let payload = WatchBridgeCodec.encode(msg)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: { [weak self] reply in
                Task { @MainActor in
                    self?.ingest(reply)
                    self?.reconnectAttempt = 0
                }
            }, errorHandler: { [weak self] _ in
                Task { @MainActor in
                    self?.softReconnectIfNeeded()
                }
            })
        } else {
            softReconnectIfNeeded()
        }
    }

    func askFlash(_ text: String, voice: Bool = false) async -> Result<String, WatchClientError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyReply) }
        guard !inFlightAsk else {
            appendDiag("Ask ignored — request already in flight")
            return .failure(.cancelled)
        }
        guard let session, session.activationState == .activated else {
            softReconnectIfNeeded()
            return .failure(.notReachable)
        }

        inFlightAsk = true
        defer { inFlightAsk = false }

        let requestId = UUID().uuidString
        activeRequestId = requestId
        let action: WatchBridgeAction = voice ? .voiceAsk : .ask
        let msg = WatchBridgeMessage(action: action, requestId: requestId, text: trimmed)
        appendDiag("Flash request started (\(voice ? "voice" : "ask"))")

        return await withCheckedContinuation { cont in
            pending[requestId] = cont
            let payload = WatchBridgeCodec.encode(msg)

            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil) { [weak self] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        // Don't fail instantly — try application context + wait.
                        try? session.updateApplicationContext(payload)
                        self.appendDiag("sendMessage failed — queued via context")
                        self.softReconnectIfNeeded()
                    }
                }
            } else {
                try? session.updateApplicationContext(payload)
                appendDiag("iPhone not reachable — queued ask")
                softReconnectIfNeeded()
            }

            // Generous timeout; brief blips should not fail first.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 45_000_000_000)
                guard let self else { return }
                guard self.activeRequestId == requestId else { return }
                if let p = self.pending.removeValue(forKey: requestId) {
                    self.appendDiag("Flash request timeout")
                    p.resume(returning: .failure(.server(WatchUserFacingError.unreachable)))
                }
            }
        }
    }

    func cancelActiveAsk() {
        if let rid = activeRequestId, let p = pending.removeValue(forKey: rid) {
            p.resume(returning: .failure(.cancelled))
        }
        activeRequestId = nil
        inFlightAsk = false
    }

    // MARK: - Reconnect

    private func softReconnectIfNeeded() {
        let away = Date().timeIntervalSince(lastReachableAt)
        if phoneReachable {
            watchPhoneLink = .connected
            return
        }
        // Brief drop — show reconnecting, not error.
        if away < 8 {
            watchPhoneLink = .reconnecting
        } else if watchPhoneLink != .reconnecting {
            watchPhoneLink = .reconnecting
        }

        guard reconnectTask == nil else { return }
        reconnectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.reconnectTask = nil }
            while !Task.isCancelled {
                self.reconnectAttempt += 1
                let delay = min(8.0, pow(1.6, Double(min(self.reconnectAttempt, 6))))
                self.appendDiag("Reconnect attempt \(self.reconnectAttempt)")
                self.session?.activate()
                self.refreshStatus()
                if self.phoneReachable {
                    self.reconnectAttempt = 0
                    self.watchPhoneLink = .connected
                    self.appendDiag("Connection restored")
                    WatchHaptics.selection()
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if self.reconnectAttempt >= 8 {
                    self.watchPhoneLink = .offline
                    self.appendDiag("WatchConnectivity unavailable")
                    return
                }
            }
        }
    }

    private func updateWatchPhoneLink(reachable: Bool, activated: Bool) {
        if !activated {
            watchPhoneLink = .connecting
            return
        }
        if reachable {
            lastReachableAt = Date()
            watchPhoneLink = .connected
            phoneReachable = true
        } else {
            phoneReachable = false
            if watchPhoneLink == .connected || watchPhoneLink == .connecting {
                watchPhoneLink = .reconnecting
            }
        }
        var s = snapshot
        s.phoneReachable = reachable
        s.watchPhoneLink = watchPhoneLink
        snapshot = s
    }

    private func ingest(_ dict: [String: Any]) {
        guard let msg = WatchBridgeCodec.decode(dict) else { return }
        switch msg.action {
        case .statusSnapshot:
            if var snap = msg.snapshot {
                snap.watchPhoneLink = phoneReachable ? .connected : watchPhoneLink
                // Never keep technical codes in UI field.
                if let err = snap.lastUserError {
                    snap.lastUserError = WatchUserFacingError.sanitize(err)
                }
                // Don't flash error phase for soft reconnect.
                if snap.phase == .error, watchPhoneLink == .reconnecting {
                    snap.phase = .connecting
                    snap.statusLine = WatchUserFacingError.restoring
                }
                snapshot = snap
                phoneReachable = snap.phoneReachable || phoneReachable
                if phoneReachable { watchPhoneLink = .connected }
            }
        case .askReply, .voiceReply:
            guard let rid = msg.requestId else { return }
            guard rid == activeRequestId || pending[rid] != nil else {
                appendDiag("Ignored stale reply \(rid.prefix(6))")
                return
            }
            guard let cont = pending.removeValue(forKey: rid) else { return }
            if activeRequestId == rid { activeRequestId = nil }
            if let err = msg.error, !err.isEmpty {
                appendDiag("Flash request error")
                cont.resume(returning: .failure(.server(WatchUserFacingError.sanitize(err))))
            } else if let text = msg.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                var s = snapshot
                s.lastAnswer = text
                s.phase = .idle
                s.statusLine = "Ready"
                s.lastUserError = nil
                snapshot = s
                appendDiag("Response received / delivered")
                cont.resume(returning: .success(text))
            } else {
                cont.resume(returning: .failure(.emptyReply))
            }
        case .lastAnswer:
            if let t = msg.text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                var s = snapshot
                s.lastAnswer = t
                snapshot = s
            }
        case .pong:
            appendDiag("Pong from iPhone")
            watchPhoneLink = .connected
        default:
            break
        }
    }

    private func appendDiag(_ message: String) {
        let stamp = Self.timeFormatter.string(from: Date())
        let line = "[\(stamp)] \(message)"
        diagnosticLines.append(line)
        if diagnosticLines.count > 40 {
            diagnosticLines.removeFirst(diagnosticLines.count - 40)
        }
        log.info("\(message, privacy: .public)")
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

extension WatchSessionClient: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            isActivated = activationState == .activated
            phoneReachable = session.isReachable
            if activationState == .activated {
                appendDiag("Watch session activated")
                if session.isReachable {
                    appendDiag("iPhone reachable")
                }
                updateWatchPhoneLink(reachable: session.isReachable, activated: true)
                let ctx = session.receivedApplicationContext
                if !ctx.isEmpty { ingest(ctx) }
                refreshStatus()
            } else {
                watchPhoneLink = .reconnecting
                softReconnectIfNeeded()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            phoneReachable = session.isReachable
            updateWatchPhoneLink(reachable: session.isReachable, activated: session.activationState == .activated)
            if session.isReachable {
                appendDiag("iPhone reachable")
                refreshStatus()
            } else {
                appendDiag("iPhone unreachable — soft reconnect")
                softReconnectIfNeeded()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in ingest(message) }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            ingest(message)
            replyHandler(WatchBridgeCodec.encode(WatchBridgeMessage(action: .pong)))
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in ingest(applicationContext) }
    }
}
