import Foundation
import UIKit

/// Shared between main app and keyboard extension.
/// Primary: App Group. Fallback: named pasteboard (SideStore-friendly when App Groups fail).
enum CompanionCredentials {
    static let appGroupId = "group.de.noco.nocoai"
    private static let pasteboardName = UIPasteboard.Name("de.noco.nocoai.creds.v1")

    private static var suite: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }

    private static var credentialsFileURL: URL? {
        containerURL?.appendingPathComponent("companion-credentials.json", isDirectory: false)
    }

    private static var bridgePasteboard: UIPasteboard {
        UIPasteboard(name: pasteboardName, create: true) ?? .general
    }

    private enum Keys {
        static let host = "nocoai.host"
        static let port = "nocoai.port"
        static let token = "nocoai.token"
        static let device = "nocoai.device"
        static let kbHost = "nocoai.kb.host"
        static let kbPort = "nocoai.kb.port"
        static let kbToken = "nocoai.kb.token"
        static let kbDevice = "nocoai.kb.device"
    }

    private struct DiskPayload: Codable {
        var host: String
        var port: Int
        var token: String
        var device: String
        var updatedAt: TimeInterval?
    }

    static var host: String {
        get {
            if let h = suite?.string(forKey: Keys.host), !h.isEmpty { return h }
            if let h = readDisk()?.host, !h.isEmpty { return h }
            if let h = UserDefaults.standard.string(forKey: Keys.kbHost), !h.isEmpty { return h }
            if let h = readPasteboard()?.host, !h.isEmpty { return h }
            return UserDefaults.standard.string(forKey: Keys.host) ?? ""
        }
        set {
            suite?.set(newValue, forKey: Keys.host)
            UserDefaults.standard.set(newValue, forKey: Keys.host)
            UserDefaults.standard.set(newValue, forKey: Keys.kbHost)
            writeDisk()
        }
    }

    static var port: Int {
        get {
            let g = suite?.integer(forKey: Keys.port) ?? 0
            if g != 0 { return g }
            if let p = readDisk()?.port, p != 0 { return p }
            let kb = UserDefaults.standard.integer(forKey: Keys.kbPort)
            if kb != 0 { return kb }
            if let p = readPasteboard()?.port, p != 0 { return p }
            let s = UserDefaults.standard.integer(forKey: Keys.port)
            return s == 0 ? 4747 : s
        }
        set {
            suite?.set(newValue, forKey: Keys.port)
            UserDefaults.standard.set(newValue, forKey: Keys.port)
            UserDefaults.standard.set(newValue, forKey: Keys.kbPort)
            writeDisk()
        }
    }

    static var token: String? {
        get {
            if let t = suite?.string(forKey: Keys.token), !t.isEmpty { return t }
            if let t = readDisk()?.token, !t.isEmpty { return t }
            if let t = UserDefaults.standard.string(forKey: Keys.kbToken), !t.isEmpty { return t }
            if let t = readPasteboard()?.token, !t.isEmpty { return t }
            return KeychainService.load(account: Keys.token)
        }
        set {
            if let newValue, !newValue.isEmpty {
                suite?.set(newValue, forKey: Keys.token)
                UserDefaults.standard.set(newValue, forKey: Keys.kbToken)
                KeychainService.save(newValue, account: Keys.token)
            } else {
                suite?.removeObject(forKey: Keys.token)
                UserDefaults.standard.removeObject(forKey: Keys.kbToken)
                KeychainService.delete(account: Keys.token)
            }
            writeDisk()
        }
    }

    static var deviceName: String {
        get {
            suite?.string(forKey: Keys.device)
                ?? readDisk()?.device
                ?? UserDefaults.standard.string(forKey: Keys.kbDevice)
                ?? readPasteboard()?.device
                ?? UserDefaults.standard.string(forKey: Keys.device)
                ?? "iPhone"
        }
        set {
            suite?.set(newValue, forKey: Keys.device)
            UserDefaults.standard.set(newValue, forKey: Keys.device)
            UserDefaults.standard.set(newValue, forKey: Keys.kbDevice)
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
        containerURL != nil
    }

    static func sync(host: String, port: Int, token: String?, deviceName: String) {
        let payload = DiskPayload(
            host: host,
            port: port == 0 ? 4747 : port,
            token: token ?? "",
            device: deviceName,
            updatedAt: Date().timeIntervalSince1970
        )

        suite?.set(payload.host, forKey: Keys.host)
        suite?.set(payload.port, forKey: Keys.port)
        suite?.set(payload.device, forKey: Keys.device)
        UserDefaults.standard.set(payload.host, forKey: Keys.host)
        UserDefaults.standard.set(payload.port, forKey: Keys.port)
        UserDefaults.standard.set(payload.device, forKey: Keys.device)
        UserDefaults.standard.set(payload.host, forKey: Keys.kbHost)
        UserDefaults.standard.set(payload.port, forKey: Keys.kbPort)
        UserDefaults.standard.set(payload.device, forKey: Keys.kbDevice)

        if !payload.token.isEmpty {
            suite?.set(payload.token, forKey: Keys.token)
            UserDefaults.standard.set(payload.token, forKey: Keys.kbToken)
            KeychainService.save(payload.token, account: Keys.token)
        } else {
            suite?.removeObject(forKey: Keys.token)
            UserDefaults.standard.removeObject(forKey: Keys.kbToken)
            KeychainService.delete(account: Keys.token)
        }
        suite?.synchronize()
        UserDefaults.standard.synchronize()
        writeDisk(payload)
        writePasteboard(payload)
    }

    static func clear() {
        suite?.removeObject(forKey: Keys.host)
        suite?.removeObject(forKey: Keys.port)
        suite?.removeObject(forKey: Keys.token)
        suite?.removeObject(forKey: Keys.device)
        suite?.synchronize()
        for key in [Keys.host, Keys.port, Keys.token, Keys.device, Keys.kbHost, Keys.kbPort, Keys.kbToken, Keys.kbDevice] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        KeychainService.delete(account: Keys.token)
        if let url = credentialsFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        bridgePasteboard.items = []
    }

    @discardableResult
    static func refreshFromDisk() -> Bool {
        if let disk = readDisk(), !disk.token.isEmpty, !disk.host.isEmpty {
            cacheLocally(disk)
            return true
        }
        if let pb = readPasteboard(), !pb.token.isEmpty, !pb.host.isEmpty {
            cacheLocally(pb)
            suite?.set(pb.host, forKey: Keys.host)
            suite?.set(pb.port, forKey: Keys.port)
            suite?.set(pb.token, forKey: Keys.token)
            suite?.set(pb.device, forKey: Keys.device)
            suite?.synchronize()
            writeDisk(pb)
            return true
        }
        if let t = UserDefaults.standard.string(forKey: Keys.kbToken), !t.isEmpty,
           let h = UserDefaults.standard.string(forKey: Keys.kbHost), !h.isEmpty {
            return true
        }
        return isConfigured
    }

    private static func cacheLocally(_ payload: DiskPayload) {
        UserDefaults.standard.set(payload.host, forKey: Keys.kbHost)
        UserDefaults.standard.set(payload.port, forKey: Keys.kbPort)
        UserDefaults.standard.set(payload.token, forKey: Keys.kbToken)
        UserDefaults.standard.set(payload.device, forKey: Keys.kbDevice)
        UserDefaults.standard.synchronize()
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
        let body: DiskPayload
        if let payload {
            body = payload
        } else {
            let hostVal = suite?.string(forKey: Keys.host)
                ?? UserDefaults.standard.string(forKey: Keys.kbHost)
                ?? UserDefaults.standard.string(forKey: Keys.host)
                ?? ""
            let portG = suite?.integer(forKey: Keys.port) ?? 0
            let portKb = UserDefaults.standard.integer(forKey: Keys.kbPort)
            let portS = UserDefaults.standard.integer(forKey: Keys.port)
            let portVal = portG != 0 ? portG : (portKb != 0 ? portKb : (portS == 0 ? 4747 : portS))
            let tokenVal = suite?.string(forKey: Keys.token)
                ?? UserDefaults.standard.string(forKey: Keys.kbToken)
                ?? KeychainService.load(account: Keys.token)
                ?? ""
            let deviceVal = suite?.string(forKey: Keys.device)
                ?? UserDefaults.standard.string(forKey: Keys.kbDevice)
                ?? UserDefaults.standard.string(forKey: Keys.device)
                ?? "iPhone"
            body = DiskPayload(host: hostVal, port: portVal, token: tokenVal, device: deviceVal, updatedAt: Date().timeIntervalSince1970)
        }
        guard !body.host.isEmpty, !body.token.isEmpty else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(body) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func writePasteboard(_ payload: DiskPayload) {
        guard !payload.host.isEmpty, !payload.token.isEmpty,
              let data = try? JSONEncoder().encode(payload) else { return }
        let encoded = "nocoai-cred:" + data.base64EncodedString()
        let pb = bridgePasteboard
        pb.items = []
        pb.setData(data, forPasteboardType: "public.data")
        pb.string = encoded
        // Prefer named pasteboard only. General pasteboard only if App Group is unavailable.
        let suiteOK = UserDefaults(suiteName: appGroupId)?.string(forKey: Keys.host)?.isEmpty == false
        if !suiteOK {
            UIPasteboard.general.string = encoded
        }
    }

    private static func readPasteboard() -> DiskPayload? {
        let pb = bridgePasteboard
        if let data = pb.data(forPasteboardType: "public.data"),
           let payload = try? JSONDecoder().decode(DiskPayload.self, from: data),
           !payload.host.isEmpty, !payload.token.isEmpty {
            return payload
        }
        if let s = pb.string, s.hasPrefix("nocoai-cred:"),
           let data = Data(base64Encoded: String(s.dropFirst("nocoai-cred:".count))),
           let payload = try? JSONDecoder().decode(DiskPayload.self, from: data),
           !payload.host.isEmpty, !payload.token.isEmpty {
            return payload
        }
        if let s = UIPasteboard.general.string, s.hasPrefix("nocoai-cred:"),
           let data = Data(base64Encoded: String(s.dropFirst("nocoai-cred:".count))),
           let payload = try? JSONDecoder().decode(DiskPayload.self, from: data),
           !payload.host.isEmpty, !payload.token.isEmpty {
            return payload
        }
        return nil
    }
}
