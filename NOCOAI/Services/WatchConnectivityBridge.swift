import Foundation
import WatchConnectivity
import os

/// iPhone-side bridge: Watch sends asks → iPhone relays to Companion (Flash only).
@MainActor
final class WatchConnectivityBridge: NSObject, ObservableObject {
    static let shared = WatchConnectivityBridge()

    private weak var connection: ConnectionStore?
    private var session: WCSession?
    private var inFlightRequestIds = Set<String>()
    private let log = Logger(subsystem: "de.noco.nocoai", category: "WatchBridge")

    func bind(connection: ConnectionStore) {
        self.connection = connection
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
        session = s
        log.info("Watch bridge bound + activating")
    }

    /// Push current status to paired Watch.
    func pushSnapshot(_ snapshot: WatchStatusSnapshot) {
        guard let session, session.activationState == .activated else { return }
        let msg = WatchBridgeMessage(action: .statusSnapshot, snapshot: snapshot)
        let payload = WatchBridgeCodec.encode(msg)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] _ in
                try? session.updateApplicationContext(payload)
                self?.log.info("Watch push via context fallback")
            }
        } else {
            try? session.updateApplicationContext(payload)
        }
    }

    func buildSnapshot(from connection: ConnectionStore) -> WatchStatusSnapshot {
        let path: WatchStatusSnapshot.ConnectionKind = {
            if !connection.isOnline { return .offline }
            switch connection.activePath {
            case .local: return .local
            case .remote: return .remote
            }
        }()

        var phase: WatchStatusSnapshot.Phase = .idle
        var statusLine = connection.isOnline ? "Ready" : "NOCO Offline"
        if connection.isReconnecting {
            phase = .connecting
            statusLine = WatchUserFacingError.restoring
        }
        if connection.speak.isRunning {
            switch connection.speak.sessionPhase {
            case .listening: phase = .listening; statusLine = "Listening…"
            case .processing: phase = .thinking; statusLine = "Thinking…"
            case .speaking: phase = .speaking; statusLine = "Speaking…"
            default: break
            }
        }
        if connection.chat.isSending, phase == .idle {
            phase = .thinking
            statusLine = "Thinking…"
        }

        var job: WatchStatusSnapshot.ActiveJob?
        if connection.images.isGenerating {
            job = WatchStatusSnapshot.ActiveJob(
                kind: "image",
                title: "Image Generation",
                progress: max(0.05, connection.images.progress),
                detail: connection.images.statusText.isEmpty ? nil : connection.images.statusText
            )
        } else if connection.chat.mode.isAgentPower && connection.chat.isSending {
            job = WatchStatusSnapshot.ActiveJob(
                kind: "agent",
                title: "NOCO Agent",
                progress: 0.5,
                detail: "Working…"
            )
        } else if connection.chat.workPhase == .executing || connection.chat.workPhase == .analyzing {
            job = WatchStatusSnapshot.ActiveJob(
                kind: "chat",
                title: "NOCO",
                progress: 0.45,
                detail: statusLine
            )
        }

        let last = connection.speak.lastReply.trimmingCharacters(in: .whitespacesAndNewlines)
        let chatLast = connection.chat.messages.last(where: { $0.role == .assistant && !$0.isStreaming })?.text ?? ""
        let resolvedLast = !last.isEmpty ? last : chatLast

        let phoneReachable = session?.isReachable ?? false
        let watchPhone: WatchLinkState = phoneReachable ? .connected : .reconnecting
        let phoneServer: WatchLinkState = {
            if connection.isReconnecting { return .reconnecting }
            if connection.isOnline { return .connected }
            return .offline
        }()
        let ollamaReady = connection.isOnline && !(connection.status.model?.isEmpty ?? true)
        let latency = connection.status.responseTimeMs.map { Int($0.rounded()) }
        let rawErr = connection.lastError?.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastErr: String? = {
            guard let e = rawErr, !e.isEmpty else { return nil }
            return WatchUserFacingError.sanitize(e)
        }()
        let techErr: String? = {
            guard let e = rawErr, !e.isEmpty else { return nil }
            let code = ConnectionDiagnostics.shared.snapshot.failureCode
            if code != .ok {
                return "\(code.rawValue): \(e)"
            }
            return e
        }()

        return WatchStatusSnapshot(
            isOnline: connection.isOnline,
            connection: path,
            modelLabel: "Flash",
            phase: phase,
            statusLine: statusLine,
            lastAnswer: String(resolvedLast.prefix(1200)),
            activeJob: job,
            phoneReachable: phoneReachable,
            watchPhoneLink: watchPhone,
            phoneServerLink: phoneServer,
            ollamaReady: ollamaReady,
            latencyMs: latency,
            lastUserError: lastErr,
            lastTechnicalError: techErr
        )
    }

    private func handleAsk(_ text: String, requestId: String, voice: Bool) async {
        if inFlightRequestIds.contains(requestId) {
            log.info("Duplicate ask \(requestId, privacy: .public) ignored")
            return
        }
        inFlightRequestIds.insert(requestId)
        defer { inFlightRequestIds.remove(requestId) }

        guard let connection else {
            reply(requestId: requestId, text: nil, error: WatchUserFacingError.phoneAway, voice: voice)
            return
        }

        // Soft wait while iPhone is reconnecting — avoid instant error flash.
        if connection.isReconnecting || !connection.isOnline {
            for attempt in 1...4 {
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 700_000_000)
                if connection.isOnline && !connection.isReconnecting { break }
            }
        }
        if connection.isReconnecting {
            reply(requestId: requestId, text: nil, error: WatchUserFacingError.restoring, voice: voice)
            return
        }
        guard connection.isOnline else {
            reply(requestId: requestId, text: nil, error: WatchUserFacingError.unreachable, voice: voice)
            return
        }

        let prompt = voice
            ? """
            [NOCO WATCH · VOICE · FLASH]
            Antworte auf Deutsch, kurz und natürlich (1–3 Sätze). Kein Markdown.
            Nutzer: \(text)
            """
            : """
            [NOCO WATCH · FLASH]
            Antworte knapp auf Deutsch (2–4 Sätze). Kein Markdown, kein Intro.
            Frage: \(text)
            """

        log.info("Flash relay start voice=\(voice, privacy: .public)")
        let replyText = await connection.chat.sendAndReturnReply(
            prompt,
            modeOverride: .flash,
            speak: false,
            displayText: text
        )
        let clean = replyText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if clean.isEmpty {
            reply(requestId: requestId, text: nil, error: WatchUserFacingError.empty, voice: voice)
        } else {
            reply(requestId: requestId, text: clean, error: nil, voice: voice)
            pushSnapshot(buildSnapshot(from: connection))
            log.info("Flash relay delivered")
        }
    }

    private func reply(requestId: String, text: String?, error: String?, voice: Bool) {
        let action: WatchBridgeAction = voice ? .voiceReply : .askReply
        let friendly = error.map { WatchUserFacingError.sanitize($0) }
        let msg = WatchBridgeMessage(action: action, requestId: requestId, text: text, error: friendly)
        sendToWatch(msg)
        if let t = text, !t.isEmpty {
            sendToWatch(WatchBridgeMessage(action: .lastAnswer, text: t))
        }
    }

    private func sendToWatch(_ message: WatchBridgeMessage) {
        guard let session, session.activationState == .activated else { return }
        let payload = WatchBridgeCodec.encode(message)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                try? session.updateApplicationContext(payload)
            }
        } else {
            try? session.updateApplicationContext(payload)
        }
    }
}

extension WatchConnectivityBridge: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            log.info("WCSession activation \(String(describing: activationState), privacy: .public)")
            if let connection {
                pushSnapshot(buildSnapshot(from: connection))
            }
            // Drain any queued application context from Watch.
            let ctx = session.receivedApplicationContext
            if !ctx.isEmpty {
                await handleIncoming(ctx)
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            log.info("Watch reachability \(session.isReachable, privacy: .public)")
            if let connection {
                pushSnapshot(buildSnapshot(from: connection))
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            await handleIncoming(message)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            await handleIncoming(message)
            if let connection {
                let snap = buildSnapshot(from: connection)
                let payload = WatchBridgeCodec.encode(
                    WatchBridgeMessage(action: .statusSnapshot, snapshot: snap)
                )
                replyHandler(payload)
            } else {
                replyHandler(WatchBridgeCodec.encode(
                    WatchBridgeMessage(action: .statusSnapshot, snapshot: .offline)
                ))
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            await handleIncoming(applicationContext)
        }
    }

    @MainActor
    private func handleIncoming(_ dict: [String: Any]) async {
        guard let msg = WatchBridgeCodec.decode(dict) else { return }
        switch msg.action {
        case .ask:
            guard let text = msg.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            let rid = msg.requestId ?? UUID().uuidString
            await handleAsk(text, requestId: rid, voice: false)
        case .voiceAsk:
            guard let text = msg.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            let rid = msg.requestId ?? UUID().uuidString
            await handleAsk(text, requestId: rid, voice: true)
        case .statusRequest:
            if let connection {
                pushSnapshot(buildSnapshot(from: connection))
            }
        case .ping:
            sendToWatch(WatchBridgeMessage(action: .pong))
        default:
            break
        }
    }
}
