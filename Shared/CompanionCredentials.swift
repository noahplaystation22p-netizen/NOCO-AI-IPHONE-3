import Foundation

/// Shared between main app and keyboard extension via App Group (+ file fallback).
enum CompanionCredentials {
    static let appGroupId = "group.de.noco.nocoai"

    private static var suite: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }

    private static var credentialsFileURL: URL? {
        containerURL?.appendingPathComponent("companion-credentials.json", isDirectory: false)
    }

    private enum Keys {
        static let host = "nocoai.host"
        static let port = "nocoai.port"
        static let token = "nocoai.token"
        static let device = "nocoai.device"
    }

    private struct DiskPayload: Codable {
        var host: String
        var port: Int
        var token: String
        var device: String
    }

    static var host: String {
        get {
            if let h = suite?.string(forKey: Keys.host), !h.isEmpty { return h }
            if let h = readDisk()?.host, !h.isEmpty { return h }
            return UserDefaults.standard.string(forKey: Keys.host) ?? ""
        }
        set {
            suite?.set(newValue, forKey: Keys.host)
            UserDefaults.standard.set(newValue, forKey: Keys.host)
            writeDisk()
        }
    }

    static var port: Int {
        get {
            let g = suite?.integer(forKey: Keys.port) ?? 0
            if g != 0 { return g }
            if let p = readDisk()?.port, p != 0 { return p }
            let s = UserDefaults.standard.integer(forKey: Keys.port)
            return s == 0 ? 4747 : s
        }
        set {
            suite?.set(newValue, forKey: Keys.port)
            UserDefaults.standard.set(newValue, forKey: Keys.port)
            writeDisk()
        }
    }

    static var token: String? {
        get {
            if let t = suite?.string(forKey: Keys.token), !t.isEmpty { return t }
            if let t = readDisk()?.token, !t.isEmpty { return t }
            return KeychainService.load(account: Keys.token)
        }
        set {
            if let newValue, !newValue.isEmpty {
                suite?.set(newValue, forKey: Keys.token)
                KeychainService.save(newValue, account: Keys.token)
            } else {
                suite?.removeObject(forKey: Keys.token)
                KeychainService.delete(account: Keys.token)
            }
            writeDisk()
        }
    }

    static var deviceName: String {
        get {
            suite?.string(forKey: Keys.device)
                ?? readDisk()?.device
                ?? UserDefaults.standard.string(forKey: Keys.device)
                ?? "iPhone"
        }
        set {
            suite?.set(newValue, forKey: Keys.device)
            UserDefaults.standard.set(newValue, forKey: Keys.device)
            writeDisk()
        }
    }

    static var baseURL: URL? {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty else { return nil }
        return URL(string: "http://\(h):\(port)/api/v1/")
    }

    static var isConfigured: Bool {
        !(token ?? "").isEmpty && !host.isEmpty
    }

    static var appGroupAvailable: Bool {
        containerURL != nil && suite != nil
    }

    static func sync(host: String, port: Int, token: String?, deviceName: String) {
        suite?.set(host, forKey: Keys.host)
        suite?.set(port, forKey: Keys.port)
        suite?.set(deviceName, forKey: Keys.device)
        UserDefaults.standard.set(host, forKey: Keys.host)
        UserDefaults.standard.set(port, forKey: Keys.port)
        UserDefaults.standard.set(deviceName, forKey: Keys.device)
        if let token, !token.isEmpty {
            suite?.set(token, forKey: Keys.token)
            KeychainService.save(token, account: Keys.token)
        } else {
            suite?.removeObject(forKey: Keys.token)
            KeychainService.delete(account: Keys.token)
        }
        suite?.synchronize()
        writeDisk(
            DiskPayload(
                host: host,
                port: port == 0 ? 4747 : port,
                token: token ?? "",
                device: deviceName
            )
        )
    }

    static func clear() {
        suite?.removeObject(forKey: Keys.host)
        suite?.removeObject(forKey: Keys.port)
        suite?.removeObject(forKey: Keys.token)
        suite?.removeObject(forKey: Keys.device)
        suite?.synchronize()
        KeychainService.delete(account: Keys.token)
        if let url = credentialsFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @discardableResult
    static func refreshFromDisk() -> Bool {
        guard let disk = readDisk(), !disk.token.isEmpty, !disk.host.isEmpty else {
            return isConfigured
        }
        suite?.set(disk.host, forKey: Keys.host)
        suite?.set(disk.port, forKey: Keys.port)
        suite?.set(disk.token, forKey: Keys.token)
        suite?.set(disk.device, forKey: Keys.device)
        suite?.synchronize()
        return true
    }

    private static func readDisk() -> DiskPayload? {
        guard let url = credentialsFileURL,
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(DiskPayload.self, from: data),
              !payload.host.isEmpty,
              !payload.token.isEmpty else { return nil }
        return payload
    }

    private static func writeDisk(_ payload: DiskPayload? = nil) {
        guard let url = credentialsFileURL else { return }
        let hostVal = suite?.string(forKey: Keys.host)
            ?? UserDefaults.standard.string(forKey: Keys.host)
            ?? ""
        let portG = suite?.integer(forKey: Keys.port) ?? 0
        let portS = UserDefaults.standard.integer(forKey: Keys.port)
        let portVal = portG != 0 ? portG : (portS == 0 ? 4747 : portS)
        let tokenVal = suite?.string(forKey: Keys.token)
            ?? KeychainService.load(account: Keys.token)
            ?? ""
        let deviceVal = suite?.string(forKey: Keys.device)
            ?? UserDefaults.standard.string(forKey: Keys.device)
            ?? "iPhone"
        let body = payload ?? DiskPayload(host: hostVal, port: portVal, token: tokenVal, device: deviceVal)
        guard !body.host.isEmpty, !body.token.isEmpty else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(body) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
