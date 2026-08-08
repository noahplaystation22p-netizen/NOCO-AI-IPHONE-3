import Foundation

/// Lightweight Companion chat client for the keyboard extension.
enum KeyboardAIClient {
    struct ChatBody: Encodable {
        let message: String
        let stream: Bool
        let mode: String
        let source: String
        let channel: String
        let display: String
        let keyboard: Bool
    }

    enum ClientError: LocalizedError {
        case notConfigured
        case badURL
        case http(Int)
        case empty
        case decode
        case cancelled
        case timedOut

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "PC nicht verbunden — NOCO AI App öffnen"
            case .badURL: return "Ungültige PC-Adresse"
            case .http(let c): return "PC-Fehler (\(c))"
            case .empty: return "Keine Antwort"
            case .decode: return "Antwort unlesbar"
            case .cancelled: return "Abgebrochen"
            case .timedOut: return "Zeitüberschreitung — nochmal tippen"
            }
        }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        // Hard UX ceiling — keyboard extensions get jetsam'd on long hangs.
        config.timeoutIntervalForRequest = 18
        config.timeoutIntervalForResource = 22
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }()

    /// Cap per-call wait so the keyboard never feels frozen.
    private static func timeout(for text: String, base: TimeInterval) -> TimeInterval {
        let n = text.count
        if n > 2500 { return min(20, max(base, 18)) }
        if n > 900 { return min(18, max(base, 16)) }
        return min(16, base)
    }

    /// Preferred path: single flash response, sanitized — logs into ⌨️ Tastatur channel.
    static func rewrite(action: KeyboardAIAction, text: String, shortenLevel: Int = 1) async throws -> String {
        let base: TimeInterval = action.isAnswer ? 16 : (action.isPrimary ? 15 : 12)
        let reply = try await post(
            message: action.prompt(for: text, shortenLevel: shortenLevel),
            display: action.displayLabel(for: text),
            timeout: timeout(for: text, base: base)
        )
        let clean = KeyboardAIAction.sanitize(reply, action: action, original: text, shortenLevel: shortenLevel)
        guard !clean.isEmpty else { throw ClientError.empty }
        return clean
    }

    /// Custom user shortcut from the NOCO AI app.
    static func rewriteCustom(shortcut: KeyboardCustomShortcut, text: String) async throws -> String {
        let reply = try await post(
            message: shortcut.fullPrompt(for: text),
            display: shortcut.displayLabel(for: text),
            timeout: timeout(for: text, base: 15)
        )
        let clean = sanitizeCustom(reply)
        guard !clean.isEmpty else { throw ClientError.empty }
        return clean
    }

    /// Free-form question → short answer (shown in keyboard Ask panel).
    static func ask(question: String) async throws -> String {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = """
        Du bist NOCO AI auf einer iPhone-Tastatur. Antworte knapp und klar (1–4 Sätze).
        Kein Intro, kein „Gerne“, kein Markdown außer nötig. Sprache der Frage übernehmen.
        Antworte auf die FRAGE selbst — nicht den Text umschreiben.

        FRAGE:
        \(q)
        """
        let reply = try await post(
            message: message,
            display: "Frage: \(q.prefix(72))",
            timeout: 16
        )
        // Light trim only — Q&A answers must stay intact for the Ask panel.
        let clean = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw ClientError.empty }
        return clean
    }

    private static func post(message: String, display: String, timeout: TimeInterval) async throws -> String {
        try Task.checkCancellation()
        CompanionCredentials.refreshFromDisk()
        KeyboardChipPreferences.refreshFromDisk()
        guard CompanionCredentials.isConfigured,
              let base = CompanionCredentials.baseURL,
              let token = CompanionCredentials.token else {
            throw ClientError.notConfigured
        }
        let url = base.appendingPathComponent("chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            ChatBody(
                message: message,
                stream: false,
                mode: "flash",
                source: "keyboard",
                channel: "keyboard",
                display: display,
                keyboard: true
            )
        )

        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else { throw ClientError.http(code) }
            guard let reply = extractReply(from: data) else { throw ClientError.decode }
            return reply
        } catch is CancellationError {
            throw ClientError.cancelled
        } catch let urlError as URLError where urlError.code == .timedOut || urlError.code == .cancelled {
            throw ClientError.timedOut
        } catch let error as ClientError {
            throw error
        } catch {
            if Task.isCancelled { throw ClientError.cancelled }
            throw error
        }
    }

    private static func sanitizeCustom(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let banned = [
            "gerne", "hier ist", "hier sind", "sure", "of course", "certainly",
            "here is", "here's", "please provide", "please give", "gib mir den"
        ]
        var lines = s.components(separatedBy: .newlines)
        if let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           banned.contains(where: { first.hasPrefix($0) }),
           lines.count > 1 {
            lines.removeFirst()
            s = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let askNeedles = ["please provide", "gib mir den text", "welcher text", "send me the text"]
        if askNeedles.contains(where: { s.lowercased().contains($0) }) {
            return ""
        }
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("„") && s.hasSuffix("“")) {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if s.hasPrefix("```") {
            s = s.replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
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
