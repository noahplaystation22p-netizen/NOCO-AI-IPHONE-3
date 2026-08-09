import Foundation

enum HostSanitizer {
    struct Parsed {
        let host: String
        let port: Int?
    }

    /// Akzeptiert: `192.168.178.197`, `http://192.168.178.197:4747/api/v1`, `192.168.178.197:4747`,
    /// auch kaputte Eingaben wie `http://https://100.x.x.x`.
    static func parse(_ input: String, defaultPort: Int = 4747) -> Parsed? {
        var text = stripSchemesAndPath(input)
        guard !text.isEmpty else { return nil }

        if let colon = text.lastIndex(of: ":"), text.filter({ $0 == ":" }).count == 1 {
            let hostPart = String(text[..<colon]).trimmingCharacters(in: .whitespaces)
            let portPart = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if let port = Int(portPart), (1...65535).contains(port), !hostPart.isEmpty {
                return Parsed(host: hostPart, port: port)
            }
        }

        let host = text.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return nil }
        return Parsed(host: host, port: nil)
    }

    /// Nur Hostname/IP — nie Schema, Port oder Pfad. Ideal für `http://\(host):port/…`.
    static func hostOnly(_ input: String) -> String {
        if let parsed = parse(input) {
            return parsed.host
        }
        return stripSchemesAndPath(input)
    }

    /// Entfernt wiederholte `http(s)://`, Pfade und Whitespace.
    private static func stripSchemesAndPath(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        // Collapse nested / duplicated schemes: http://https://100.64.0.1
        var changed = true
        while changed {
            changed = false
            let lower = text.lowercased()
            if lower.hasPrefix("https://") {
                text = String(text.dropFirst(8))
                changed = true
                continue
            }
            if lower.hasPrefix("http://") {
                text = String(text.dropFirst(7))
                changed = true
                continue
            }
            // Bare scheme without slashes (rare paste artifacts)
            if lower.hasPrefix("https:") {
                text = String(text.dropFirst(6)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                changed = true
                continue
            }
            if lower.hasPrefix("http:") {
                text = String(text.dropFirst(5)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                changed = true
            }
        }

        if let slash = text.firstIndex(of: "/") {
            text = String(text[..<slash])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Tailscale CGNAT 100.64.0.0/10
    static func isTailscaleIP(_ host: String) -> Bool {
        let parts = hostOnly(host).split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 100 && parts[1] >= 64 && parts[1] <= 127
    }

    /// RFC1918 only (no APIPA 169.254 — not reachable for pairing).
    static func isPrivateLanIP(_ host: String) -> Bool {
        let parts = hostOnly(host).split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        if parts[0] == 10 { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31 { return true }
        return false
    }

    static func isLinkLocalIP(_ host: String) -> Bool {
        let parts = hostOnly(host).split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 169 && parts[1] == 254
    }

    /// Usable companion host for pairing / API calls.
    static func isPairableHost(_ host: String) -> Bool {
        let h = hostOnly(host)
        guard !h.isEmpty else { return false }
        if isLinkLocalIP(h) || h == "127.0.0.1" { return false }
        return isPrivateLanIP(h) || isTailscaleIP(h)
    }

    static func classify(_ host: String) -> ConnectionPathKind {
        if isTailscaleIP(host) { return .remote }
        return .local
    }
}

enum ConnectionPathKind: String, Codable {
    case local
    case remote

    var label: String {
        switch self {
        case .local: return "Lokal verbunden"
        case .remote: return "Tailscale Remote"
        }
    }

    var shortLabel: String {
        switch self {
        case .local: return "Local"
        case .remote: return "Tailscale Remote"
        }
    }
}
