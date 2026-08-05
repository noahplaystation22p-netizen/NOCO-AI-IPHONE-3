import Foundation
import UIKit
import Combine

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
    @Published var pendingDeepLink: PairingDeepLink?
    @Published var localNetworkHint: String?
    @Published var features: FeaturesResponse?
    /// Tab to open after notification / deep link (0 Chat, 1 Bildideen, 2 Studio)
    @Published var pendingTab: Int?
    /// Open this gallery image after switching to Bildideen
    @Published var pendingGalleryImageURL: URL?
    @Published var pendingGalleryImageId: String?

    let chat = ChatStore()
    let images = ImageStore()
    let code = CodeStore()
    let speak = SpeakSessionController()
    let profile = UserProfileStore()

    private var token: String?
    private var pollTask: Task<Void, Never>?
    private var api: CompanionAPI?
    private var cancellables = Set<AnyCancellable>()
    /// Hysteresis: require several consecutive failures before marking offline
    private var consecutiveFailures = 0
    private let offlineFailureThreshold = 5

    private enum Keys {
        static let host = "nocoai.host"
        static let port = "nocoai.port"
        static let token = "nocoai.token"
        static let device = "nocoai.device"
    }

    init() {
        forwardStoreChanges()
        let storedHost = UserDefaults.standard.string(forKey: Keys.host) ?? ""
        serverHost = HostSanitizer.hostOnly(storedHost)
        serverPort = UserDefaults.standard.integer(forKey: Keys.port)
        if serverPort == 0 { serverPort = 4747 }
        deviceName = UserDefaults.standard.string(forKey: Keys.device) ?? UIDevice.current.name
        token = KeychainService.load(account: Keys.token)
        isPaired = token != nil && !serverHost.isEmpty
        rebuildAPI()
        speak.bind(connection: self)
        // Keep keyboard extension credentials in sync
        CompanionCredentials.sync(
            host: serverHost,
            port: serverPort,
            token: token,
            deviceName: deviceName
        )
        if isPaired {
            prepareLocalNetworkAccess(host: serverHost, port: serverPort)
            chat.restoreSession()
            startPolling()
            bindStores()
            Task { await bootstrapAfterPair() }
        }
    }

    var baseURLString: String {
        "http://\(serverHost):\(serverPort)/api/v1/"
    }

    /// Call when app returns to foreground to keep Local Network permission warm.
    func onForeground() {
        images.handleDidBecomeActive()
        AppNotificationService.clearBadge()
        CompanionCredentials.sync(
            host: serverHost,
            port: serverPort,
            token: token,
            deviceName: deviceName
        )
        if isPaired, !serverHost.isEmpty {
            prepareLocalNetworkAccess(host: serverHost, port: serverPort)
            chat.startSyncLoop()
            Task { await refreshStatus() }
        }
        consumePendingSpeakLaunchIfNeeded()
    }

    func onBackground() {
        images.handleDidEnterBackground()
        if speak.isRunning {
            speak.ensureBackgroundPresence()
        }
    }

    func rebuildAPI() {
        guard !serverHost.isEmpty,
              let url = URL(string: baseURLString) else {
            api = nil
            return
        }
        api = CompanionAPI(baseURL: url, token: token)
        bindStores()
    }

    private func bindStores() {
        chat.bind(api: api, host: serverHost, port: serverPort)
        images.bind(api: api, host: serverHost, port: serverPort)
        images.onGenerationFinished = { [weak self] conversationId, prompt, url, data in
            Task { @MainActor in
                await self?.handleImageGenerationFinished(
                    conversationId: conversationId,
                    prompt: prompt,
                    url: url,
                    data: data
                )
            }
        }
        code.bind(api: api)
        profile.bind(api: api)
    }

    func openGalleryImage(url: URL?, serverId: String?) {
        pendingGalleryImageURL = url
        pendingGalleryImageId = serverId
        pendingTab = 1
        Task { await refreshGallery() }
    }

    func clearPendingGalleryFocus() {
        pendingGalleryImageURL = nil
        pendingGalleryImageId = nil
    }

    private func handleImageGenerationFinished(
        conversationId: String?,
        prompt: String,
        url: URL?,
        data: Data?
    ) async {
        // Stay on Bildideen — PC already focuses the Bild-chat via sync.
        await chat.loadConversations()
        await images.loadFromConversations(chat.conversations, api: api)
        openImagesTab()
    }

    private func bootstrapAfterPair() async {
        chat.restoreSession()
        chat.startSyncLoop()
        await chat.loadConversations()
        await code.loadSessions()
        await loadFeatures()
        await images.loadFromConversations(chat.conversations, api: api)
        await profile.pullRemote()
        if !profile.profile.userName.isEmpty || !profile.profile.facts.isEmpty {
            await profile.pushRemote()
        }
    }

    func loadFeatures() async {
        guard let api else { return }
        features = try? await api.fetchFeatures()
    }

    func refreshGallery() async {
        await chat.loadConversations()
        await images.loadFromConversations(chat.conversations, api: api)
    }

    private func forwardStoreChanges() {
        chat.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        images.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        code.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        speak.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        profile.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        speak.voice.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
            self?.speak.pushLiveActivity(force: false)
        }.store(in: &cancellables)
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
            CompanionCredentials.sync(
                host: serverHost,
                port: serverPort,
                token: response.token,
                deviceName: deviceName
            )
            isPaired = true
            consecutiveFailures = 0
            rebuildAPI()
            HapticService.success()
            await refreshStatus()
            startPolling()
            await bootstrapAfterPair()
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
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        if host == "keyboard-sync" || host == "sync" {
            CompanionCredentials.sync(
                host: serverHost,
                port: serverPort,
                token: token,
                deviceName: deviceName
            )
            return
        }
        if host == "speak" || path.contains("speak") || host == "siri" {
            launchSpeakFromShortcut()
            return
        }
        if host == "images" || host == "bildideen" || path.contains("images") || path.contains("bild") {
            pendingTab = 1
            return
        }
        guard let link = PairingDeepLink.from(url: url) else { return }
        applyDeepLink(link)
        if let pin = link.pin, !pin.isEmpty {
            Task { await pair(host: link.host, port: link.port, pin: pin) }
        }
    }

    /// Shortcuts / Siri / `nocoai://speak` — works even after cold start.
    func launchSpeakFromShortcut() {
        SpeakLaunchBridge.pendingStart = true
        // Don't present Speak sheet — Live Activity + audio keep session usable in background
        Task { @MainActor in
            for _ in 0..<40 {
                if isPaired && isOnline { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
                await refreshStatus(showLoading: false)
            }
            guard SpeakLaunchBridge.pendingStart else { return }
            if isOnline {
                if !speak.isRunning {
                    speak.start()
                }
                SpeakLaunchBridge.clearPending()
                HapticService.success()
            } else {
                speak.openUI()
                speak.statusLine = "PC offline — Companion starten, dann nochmal Shortcut"
            }
        }
    }

    func stopSpeakFromShortcut() {
        SpeakLaunchBridge.clearPending()
        speak.stop()
        speak.showSpeakUI = false
    }

    func consumePendingSpeakLaunchIfNeeded() {
        guard SpeakLaunchBridge.pendingStart else { return }
        launchSpeakFromShortcut()
    }

    func openImagesTab() {
        pendingTab = 1
    }

    func applyQRCode(_ raw: String) {
        guard let link = PairingDeepLink.parse(from: raw) else {
            lastError = "QR-Code konnte nicht gelesen werden"
            return
        }
        applyDeepLink(link)
        HapticService.light()
    }

    /// One-scan pairing: QR contains host + pin → connect immediately
    func pairFromQR(_ raw: String) async {
        guard let link = PairingDeepLink.parse(from: raw) else {
            lastError = "QR-Code ungültig — in NOCO AI X neu öffnen"
            HapticService.error()
            return
        }
        guard let pin = link.pin, !pin.isEmpty else {
            lastError = "QR ohne PIN — bitte neuen Code in NOCO AI X öffnen"
            HapticService.error()
            return
        }
        lastError = nil
        await pair(host: link.host, port: link.port, pin: pin)
    }

    func refreshStatus(showLoading: Bool = false) async {
        guard let api else { return }
        if showLoading { isRefreshing = true }
        defer { if showLoading { isRefreshing = false } }

        do {
            let newStatus = try await api.fetchStatus()
            status = newStatus
            // Companion reachable = online (independent of Ollama / AI readiness)
            consecutiveFailures = 0
            isOnline = true
            lastError = nil
            await loadFeatures()
        } catch {
            consecutiveFailures += 1
            if consecutiveFailures >= offlineFailureThreshold {
                isOnline = false
            }
            if let err = error as? CompanionAPIError, case .unauthorized = err {
                disconnect()
                lastError = err.localizedDescription
            }
        }
    }

    func disconnect() {
        speak.stop()
        pollTask?.cancel()
        pollTask = nil
        chat.stopSync()
        token = nil
        isPaired = false
        isOnline = false
        consecutiveFailures = 0
        KeychainService.delete(account: Keys.token)
        CompanionCredentials.clear()
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
                try? await Task.sleep(nanoseconds: 8_000_000_000)
            }
        }
    }
}
