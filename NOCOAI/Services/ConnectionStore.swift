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
    @Published var lastError: String?
    @Published var messages: [ChatMessage] = []
    @Published var isSending = false

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

    func pair(host: String, port: Int, pin: String) async {
        serverHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        serverPort = port
        lastError = nil
        rebuildAPI()
        guard let api else {
            lastError = "Ungültige Adresse"
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let response = try await api.pair(pin: pin, deviceName: deviceName)
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
            lastError = error.localizedDescription
            HapticService.error()
        }
    }

    func discoverAndPair(pin: String) async {
        lastError = nil
        isRefreshing = true
        defer { isRefreshing = false }

        if !serverHost.isEmpty, let url = URL(string: baseURLString) {
            let probe = CompanionAPI(baseURL: url, token: nil)
            do {
                _ = try await probe.fetchPairing()
                rebuildAPI()
                await pair(host: serverHost, port: serverPort, pin: pin)
                return
            } catch {
                // fall through to manual host requirement
            }
        }

        lastError = "Bitte PC-IP eingeben und PIN aus NOCO AI übernehmen."
        HapticService.error()
    }

    func refreshStatus() async {
        guard let api else { return }
        isRefreshing = true
        defer { isRefreshing = false }
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
                messages[idx].text = "Fehler: \(error.localizedDescription)"
                messages[idx].isStreaming = false
            }
            lastError = error.localizedDescription
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
