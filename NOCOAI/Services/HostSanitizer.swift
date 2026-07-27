import Foundation

enum HostSanitizer {
    struct Parsed {
        let host: String
        let port: Int?
    }

    /// Akzeptiert: `192.168.178.197`, `http://192.168.178.197:4747/api/v1`, `192.168.178.197:4747`
    static func parse(_ input: String, defaultPort: Int = 4747) -> Parsed? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text.contains("://") {
            var urlString = text
            if !urlString.lowercased().hasPrefix("http") {
                urlString = "http://\(urlString)"
            }
            if let url = URL(string: urlString), let host = url.host, !host.isEmpty {
                return Parsed(host: host, port: url.port ?? defaultPort)
            }
        }

        text = text
            .replacingOccurrences(of: "https://", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "http://", with: "", options: .caseInsensitive)

        if let slash = text.firstIndex(of: "/") {
            text = String(text[..<slash])
        }

        if let colon = text.lastIndex(of: ":"), text.filter({ $0 == ":" }).count == 1 {
            let hostPart = String(text[..<colon]).trimmingCharacters(in: .whitespaces)
            let portPart = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if let port = Int(portPart), !hostPart.isEmpty {
                return Parsed(host: hostPart, port: port)
            }
        }

        let host = text.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return nil }
        return Parsed(host: host, port: nil)
    }

    static func hostOnly(_ input: String) -> String {
        parse(input)?.host ?? input
            .replacingOccurrences(of: "https://", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "http://", with: "", options: .caseInsensitive)
            .split(separator: "/").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? input
    }
}
