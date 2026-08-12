import Foundation
import WatchConnectivity

/// Watch-side WatchConnectivity client — all AI goes through iPhone.
@MainActor
final class WatchSessionClient: NSObject, ObservableObject {
    static let shared = WatchSessionClient()

    @Published private(set) var snapshot: WatchStatusSnapshot = .offline
    @Published private(set) var phoneReachable = false
    @Published private(set) var isActivated = false

    private var session: WCSession?
    private var pending: [String: CheckedContinuation<Result<String, WatchClientError>, Never>] = [:]

    enum WatchClientError: LocalizedError {
        case notReachable
        case emptyReply
        case server(String)

        var errorDescription: String? {
            switch self {
            case .notReachable: return "iPhone nicht erreichbar."
            case .emptyReply: return "Keine Antwort erhalten."
            case .server(let m): return m
            }
        }
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
        session = s
    }

    func refreshStatus() {
        guard let session, session.activationState == .activated else { return }
        let msg = WatchBridgeMessage(action: .statusRequest)
        let payload = WatchBridgeCodec.encode(msg)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: { [weak self] reply in
                Task { @MainActor in
                    self?.ingest(reply)
                }
            }, errorHandler: nil)
        }
    }

    func askFlash(_ text: String, voice: Bool = false) async -> Result<String, WatchClientError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyReply) }
        guard let session, session.activationState == .activated else {
            return .failure(.notReachable)
        }

        let requestId = UUID().uuidString
        let action: WatchBridgeAction = voice ? .voiceAsk : .ask
        let msg = WatchBridgeMessage(action: action, requestId: requestId, text: trimmed)

        return await withCheckedContinuation { cont in
            pending[requestId] = cont
            let payload = WatchBridgeCodec.encode(msg)

            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil) { [weak self] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        if let p = self.pending.removeValue(forKey: requestId) {
                            p.resume(returning: .failure(.notReachable))
                        }
                    }
                }
            } else {
                // Queue via context — iPhone picks up when reachable; short timeout.
                try? session.updateApplicationContext(payload)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 12_000_000_000)
                    guard let self else { return }
                    if let p = self.pending.removeValue(forKey: requestId) {
                        p.resume(returning: .failure(.notReachable))
                    }
                }
            }

            // Safety timeout
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 28_000_000_000)
                guard let self else { return }
                if let p = self.pending.removeValue(forKey: requestId) {
                    self.pending.removeValue(forKey: requestId)
                    p.resume(returning: .failure(.server("Zeitüberschreitung — iPhone prüfen.")))
                }
            }
        }
    }

    private func ingest(_ dict: [String: Any]) {
        guard let msg = WatchBridgeCodec.decode(dict) else { return }
        switch msg.action {
        case .statusSnapshot:
            if let snap = msg.snapshot {
                snapshot = snap
                phoneReachable = snap.phoneReachable
            }
        case .askReply, .voiceReply:
            guard let rid = msg.requestId else { return }
            guard let cont = pending.removeValue(forKey: rid) else { return }
            if let err = msg.error, !err.isEmpty {
                cont.resume(returning: .failure(.server(err)))
            } else if let text = msg.text, !text.isEmpty {
                var s = snapshot
                s.lastAnswer = text
                s.phase = .idle
                snapshot = s
                cont.resume(returning: .success(text))
            } else {
                cont.resume(returning: .failure(.emptyReply))
            }
        case .lastAnswer:
            if let t = msg.text, !t.isEmpty {
                var s = snapshot
                s.lastAnswer = t
                snapshot = s
            }
        default:
            break
        }
    }
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
            let ctx = session.receivedApplicationContext
            if !ctx.isEmpty {
                ingest(ctx)
            }
            refreshStatus()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            phoneReachable = session.isReachable
            var s = snapshot
            s.phoneReachable = session.isReachable
            snapshot = s
            if session.isReachable { refreshStatus() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in ingest(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in ingest(applicationContext) }
    }
}
