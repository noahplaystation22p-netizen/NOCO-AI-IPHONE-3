import Foundation

/// Shared between main app and keyboard extension via App Group.
enum CompanionCredentials {
    static let appGroupId = "group.de.noco.nocoai"

    private static var suite: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    private enum Keys {
        static let host = "nocoai.host"
        static let port = "nocoai.port"
        static let token = "nocoai.token"
        static let device = "nocoai.device"
    }

    static var host: String {
        get { suite?.string(forKey: Keys.host) ?? UserDefaults.standard.string(forKey: Keys.host) ?? "" }
        set {
            suite?.set(newValue, forKey: Keys.host)
            UserDefaults.standard.set(newValue, forKey: Keys.host)
        }
    }

    static var port: Int {
        get {
            let g = suite?.integer(forKey: Keys.port) ?? 0
            if g != 0 { return g }
            let s = UserDefaults.standard.integer(forKey: Keys.port)
            return s == 0 ? 4747 : s
        }
        set {
            suite?.set(newValue, forKey: Keys.port)
            UserDefaults.standard.set(newValue, forKey: Keys.port)
        }
    }

    static var token: String? {
        get {
            if let t = suite?.string(forKey: Keys.token), !t.isEmpty { return t }
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
        }
    }

    static var deviceName: String {
        get {
            suite?.string(forKey: Keys.device)
                ?? UserDefaults.standard.string(forKey: Keys.device)
                ?? "iPhone"
        }
        set {
            suite?.set(newValue, forKey: Keys.device)
            UserDefaults.standard.set(newValue, forKey: Keys.device)
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

    /// Call after pairing / disconnect so the keyboard sees the same session.
    static func sync(host: String, port: Int, token: String?, deviceName: String) {
        self.host = host
        self.port = port
        self.token = token
        self.deviceName = deviceName
    }

    static func clear() {
        token = nil
        suite?.removeObject(forKey: Keys.host)
        suite?.removeObject(forKey: Keys.port)
    }
}
