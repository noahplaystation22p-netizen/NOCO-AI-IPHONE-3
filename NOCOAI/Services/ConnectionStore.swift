import Foundation
import UIKit

@MainActor
final class ConnectionStore: ObservableObject {
    @Published var isPaired = false
    @Published var serverHost = ""
    @Published var serverPort = 4747
    @Published var deviceName = UIDevice.current.name
    @Published var status = ServerStatus()
    @Published var isOnline = false
    @Published var isRefreshing = false
    @Published var isPinging = false
    @Published var pingMessage: String?
    @Published var lastError: String?
    @Published var messages: [ChatMessage] = []
    @Published var isSending = false
    @Published var pendingDeepLink: PairingDeepLink?
    @Published var localNetworkHint: String?

    private var token: String?
    private var pollTask: Task<Void, Never>?
    private var api: CompanionAPI?

    private enum Keys {
        static let host = "nocoai.host"
        static let port = "nocoai.port"
        static let token = "nocoai.token"
        static let device = "nocoai.device"
    }

    init() {
        serverHost = UserDefaults.standard.string(forKey: Keys.host) ?? ""
        serverPort = UserDefaults.standard.integer(forKey: Keys.port)
        if serverPort == 0 { serverPort = 4747 }
        deviceName = UserDefaults.standard.string(forKey: Keys.device) ?? UIDevice.current.name
        token = KeychainService.load(account: Keys.token)
        isPaired = token != nil && !serverHost.isEmpty
        rebuildAPI()
        if isPaired { startPolling() }
    }

    var baseURLString: String {
        "http://\(serverHost):\(serverPort)/api/v1"
    }

    func rebuildAPI() {
        guard !serverHost.isEmpty,
              let url = URL(string: baseURLString) else {
            api = nil
            return
        }
        api = CompanionAPI(baseURL: url, token: token)
    }

    func prepareLocalNetworkAccess(host: String, port: Int) {
        let parsed = resolveHostPort(host: host, port: port)
        guard let parsed else { return }
        localNetworkHint = "iOS fragt ggf. nach „Lokales Netzwerk“ — bitte erlauben."
        LocalNetworkService.warmUp(targetHost: parsed.host, port: parsed.port)
    }

    func testConnection(host: String, port: Int) async -> Bool {
        guard let parsed = resolveHostPort(host: host, port: port) else {
            pingMessage = "Ungültige Adresse — nur IP eingeben, z. B. 192.168.178.197"
            return false
        }

        prepareLocalNetworkAccess(host: parsed.host, port: parsed.port)

        guard let url = URL(string: "http://\(parsed.host):\(parsed.port)/api/v1") else {
            pingMessage = "Ungültige Adresse"
            return false
        }

        isPinging = true
        pingMessage = nil
        lastError = nil
        defer { isPinging = false }

        do {
            try await CompanionAPI(baseURL: url, token: nil).ping()
            serverHost = parsed.host
            serverPort = parsed.port
            pingMessage = "PC erreichbar ✓"
            HapticService.success()
            return true
        } catch {
            pingMessage = (error as? LocalizedError)?.errorDescription
                ?? "PC nicht erreichbar. Gleiches WLAN? Firewall Port 4747? NOCO AI läuft?"
            HapticService.error()
            return false
        }
    }

    func pair(host: String, port: Int, pin: String) async {
        guard let parsed = resolveHostPort(host: host, port: port) else {
            lastError = "Ungültige IP — nur 192.168.x.x eingeben (ohne http://)"
            return
        }

        serverHost = parsed.host
        serverPort = parsed.port
        lastError = nil
        prepareLocalNetworkAccess(host: parsed.host, port: parsed.port)
        rebuildAPI()

        guard let url = URL(string: baseURLString) else {
            lastError = "Ungültige Adresse"
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let client = CompanionAPI(baseURL: url, token: nil)
            try await client.ping()
            let response = try await client.pair(pin: pin, deviceName: deviceName)
            token = response.token
            KeychainService.save(response.token, account: Keys.token)
            UserDefaults.standard.set(serverHost, forKey: Keys.host)
            UserDefaults.standard.set(serverPort, forKey: Keys.port)
            UserDefaults.standard.set(deviceName, forKey: Keys.device)
            isPaired = true
            rebuildAPI()
            HapticService.success()
            await refreshStatus()
            startPolling()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            HapticService.error()
        }
    }

    func applyDeepLink(_ link: PairingDeepLink) {
        pendingDeepLink = link
        serverHost = link.host
        serverPort = link.port
    }

    func handleIncomingURL(_ url: URL) {
        guard let link = PairingDeepLink.from(url: url) else { return }
        applyDeepLink(link)
        if isPaired, let pin = link.pin, !pin.isEmpty {
            Task { await pair(host: link.host, port: link.port, pin: pin) }
        }
    }

    func applyQRCode(_ raw: String) {
        guard let link = PairingDeepLink.parse(from: raw) else {
            lastError = "QR-Code konnte nicht gelesen werden"
            return
        }
        applyDeepLink(link)
        HapticService.light()
    }

    func refreshStatus(showLoading: Bool = false) async {
        guard let api else { return }
        if showLoading { isRefreshing = true }
        defer { if showLoading { isRefreshing = false } }

        do {
            let newStatus = try await api.fetchStatus()
            status = newStatus
            isOnline = newStatus.online
            lastError = nil
        } catch {
            isOnline = false
            if let err = error as? CompanionAPIError, case .unauthorized = err {
                disconnect()
                lastError = err.localizedDescription
            }
        }
    }

    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let api, !isSending else { return }
        isSending = true
        messages.append(ChatMessage(role: .user, text: trimmed))
        let assistant = ChatMessage(role: .assistant, text: "", isStreaming: true)
        messages.append(assistant)
        let assistantID = assistant.id
        HapticService.light()

        do {
            for try await chunk in api.streamChat(message: trimmed) {
                if let idx = messages.firstIndex(where: { $0.id == assistantID }) {
                    messages[idx].text += chunk
                }
            }
            if let idx = messages.firstIndex(where: { $0.id == assistantID }) {
                messages[idx].isStreaming = false
            }
            HapticService.success()
            await refreshStatus()
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == assistantID }) {
                messages[idx].text = "Fehler: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
                messages[idx].isStreaming = false
            }
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            HapticService.error()
        }
        isSending = false
    }

    func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        token = nil
        isPaired = false
        isOnline = false
        KeychainService.delete(account: Keys.token)
        rebuildAPI()
    }

    private func resolveHostPort(host: String, port: Int) -> (host: String, port: Int)? {
        guard let parsed = HostSanitizer.parse(host, defaultPort: port) else { return nil }
        return (parsed.host, parsed.port ?? port)
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshStatus()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }
}
