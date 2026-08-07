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
    /// Last successful companion status ping (for Online badge freshness).
    @Published var lastStatusAt: Date?
    @Published var isPinging = false
    @Published var pingMessage: String?
    @Published var lastError: String?
    /// Brief drops: keep UI calm and auto-retry instead of hard abort.
    @Published var isReconnecting = false
    @Published var reconnectStatusLine: String?
    @Published var pendingDeepLink: PairingDeepLink?
    @Published var localNetworkHint: String?
    @Published var features: FeaturesResponse?
    /// Tab to open after notification / deep link (0 Chat, 1 Bildideen, 2 Studio)
    @Published var pendingTab: Int?
    /// Open Magischer Radierer after switching to Bildideen
    @Published var pendingOpenEraser = false
    /// Open Live Screen after switching to Studio
    @Published var pendingOpenLiveScreen = false
    /// Open NOCO Agent after switching to Studio
    @Published var pendingOpenAgent = false
    /// Open Vision Live after switching to Studio
    @Published var pendingOpenVisionLive = false
    /// Prefill Chat composer when switching to Chat
    @Published var pendingChatDraft: String?
    /// Prefill Agent goal when opening Studio → Agent
    @Published var pendingAgentDraft: String?
    /// Open this gallery image after switching to Bildideen
    @Published var pendingGalleryImageURL: URL?
    @Published var pendingGalleryImageId: String?

    /// Hide floating tab chrome (e.g. Magischer Radierer full focus).
    @Published var hideMainTabBar = false

    /// LAN host for home Wi‑Fi (preferred).
    @Published var localHost = ""
    /// Tailscale / remote host (optional).
    @Published var remoteHost = ""
    @Published var activePath: ConnectionPathKind = .local
    /// When true, switch to Tailscale without asking after local fails.
    @Published var autoUseRemote = false
    /// When true, switch back to LAN automatically when home Wi‑Fi returns.
    @Published var autoSwitchToLocal = true
    @Published var showRemotePrompt = false
    @Published var showLocalAvailablePrompt = false
    @Published var pathStatusLine: String?

    let chat = ChatStore()
    let images = ImageStore()
    let code = CodeStore()
    let speak = SpeakSessionController()
    let liveScreen = LiveScreenSessionController()
    let profile = UserProfileStore()

    private var token: String?
    private var pollTask: Task<Void, Never>?
    private var api: CompanionAPI?
    private var cancellables = Set<AnyCancellable>()
    /// Hysteresis: require consecutive failures before marking offline
    private var consecutiveFailures = 0
    private let offlineFailureThreshold = 2
    /// User confirmed remote for this away stretch (cleared when back on LAN).
    private var remoteSessionApproved = false
    private var lastLocalProbeAt: Date?
    private var remotePromptSuppressedUntil: Date?
    private var lastFreshChatAt: Date?

    private enum Keys {
        static let host = "nocoai.host"
        static let port = "nocoai.port"
        static let token = "nocoai.token"
        static let device = "nocoai.device"
        static let localHost = "nocoai.localHost"
        static let remoteHost = "nocoai.remoteHost"
        static let autoUseRemote = "nocoai.autoUseRemote"
        static let autoSwitchToLocal = "nocoai.autoSwitchToLocal"
        static let activePath = "nocoai.activePath"
    }

    init() {
        forwardStoreChanges()
        let storedHost = UserDefaults.standard.string(forKey: Keys.host) ?? ""
        serverHost = HostSanitizer.hostOnly(storedHost)
        serverPort = UserDefaults.standard.integer(forKey: Keys.port)
        if serverPort == 0 { serverPort = 4747 }
        deviceName = UserDefaults.standard.string(forKey: Keys.device) ?? UIDevice.current.name
        token = KeychainService.load(account: Keys.token)
        localHost = HostSanitizer.hostOnly(UserDefaults.standard.string(forKey: Keys.localHost) ?? "")
        remoteHost = HostSanitizer.hostOnly(UserDefaults.standard.string(forKey: Keys.remoteHost) ?? "")
        // Default ON: auto Tailscale when LAN is gone — simplest remote experience.
        if UserDefaults.standard.object(forKey: Keys.autoUseRemote) == nil {
            autoUseRemote = true
            UserDefaults.standard.set(true, forKey: Keys.autoUseRemote)
        } else {
            autoUseRemote = UserDefaults.standard.bool(forKey: Keys.autoUseRemote)
        }
        if UserDefaults.standard.object(forKey: Keys.autoSwitchToLocal) == nil {
            autoSwitchToLocal = true
        } else {
            autoSwitchToLocal = UserDefaults.standard.bool(forKey: Keys.autoSwitchToLocal)
        }
        if let raw = UserDefaults.standard.string(forKey: Keys.activePath),
           let path = ConnectionPathKind(rawValue: raw) {
            activePath = path
        } else if !serverHost.isEmpty {
            activePath = HostSanitizer.classify(serverHost)
        }
        // Seed local/remote from active host if legacy install.
        if localHost.isEmpty, !serverHost.isEmpty, HostSanitizer.isPrivateLanIP(serverHost) {
            localHost = serverHost
        }
        if remoteHost.isEmpty, !serverHost.isEmpty, HostSanitizer.isTailscaleIP(serverHost) {
            remoteHost = serverHost
        }
        isPaired = token != nil && !serverHost.isEmpty
        rebuildAPI()
        speak.bind(connection: self)
        liveScreen.bind(
            apiProvider: { [weak self] in self?.companionAPI() },
            speakBusy: { [weak self] in
                guard let self else { return false }
                if self.speak.isBusyForVision { return true }
                if case .speaking = self.speak.voice.phase { return true }
                if case .processing = self.speak.voice.phase { return true }
                return false
            }
        )
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

    /// Short freshness label for the Online badge (updates as status polls).
    var onlineBadgeDetail: String? {
        guard isOnline, let at = lastStatusAt else {
            return pathStatusLine
        }
        let path = activePath == .remote ? "Remote" : "Lokal"
        let sec = Int(Date().timeIntervalSince(at))
        if sec < 3 { return "\(path) · frisch" }
        if sec < 60 { return "\(path) · vor \(sec)s" }
        let min = sec / 60
        return "\(path) · vor \(min) Min"
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
        // Fresh empty chat whenever the user comes back into the app.
        openFreshChatOnEnter()
        consumePendingSystemLaunches()
    }

    /// Clean chat on app enter (debounced) and Speak shortcut (forced).
    func openFreshChatOnEnter(force: Bool = false) {
        guard isPaired else { return }
        let now = Date()
        if !force, let last = lastFreshChatAt, now.timeIntervalSince(last) < 1.2 { return }
        lastFreshChatAt = now
        Task { @MainActor in
            await chat.beginCleanSession()
        }
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

    /// Shared Companion client for features outside Chat/Image stores (e.g. Live Screen).
    func companionAPI() -> CompanionAPI? { api }

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
        chat.onImageCreated = { [weak self] prompt, url, data in
            self?.images.ingestFromChat(prompt: prompt, url: url, data: data)
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
        // Stay wherever the user is — chat-generated images also land in the gallery.
        await chat.loadConversations()
        await images.loadFromConversations(chat.conversations, api: api)
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

    private var voiceRefreshScheduled = false
    private var chatRefreshScheduled = false

    private func forwardStoreChanges() {
        // Coalesce chat token/stream updates — avoid invalidating every hub on each chunk.
        chat.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            guard !self.chatRefreshScheduled else { return }
            self.chatRefreshScheduled = true
            let delay: UInt64 = self.chat.isSending ? 64_000_000 : 24_000_000
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: delay)
                self.chatRefreshScheduled = false
                self.objectWillChange.send()
            }
        }.store(in: &cancellables)
        images.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        code.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        speak.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        liveScreen.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        profile.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        // Voice level meters fire very often — coalesce to keep tabs smooth.
        speak.voice.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            self.speak.pushLiveActivity(force: false)
            guard !self.voiceRefreshScheduled else { return }
            self.voiceRefreshScheduled = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 64_000_000)
                self.voiceRefreshScheduled = false
                self.objectWillChange.send()
            }
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

    func pair(host: String, port: Int, pin: String, remoteHint: String? = nil, lanHint: String? = nil) async {
        guard let parsed = resolveHostPort(host: host, port: port) else {
            lastError = "Ungültige Adresse — WLAN (192.168.x.x) oder Tailscale (100.x.x.x)"
            return
        }

        serverHost = parsed.host
        serverPort = parsed.port
        lastError = nil
        rememberHosts(primary: parsed.host, remoteHint: remoteHint, lanHint: lanHint)
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
        // Prefer path/host route names before treating host as a pairing IP.
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        let route = host.isEmpty ? path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) : host

        if route == "keyboard-sync" || route == "sync" || path.contains("keyboard-sync") {
            CompanionCredentials.sync(
                host: serverHost,
                port: serverPort,
                token: token ?? KeychainService.load(account: "nocoai.token"),
                deviceName: deviceName
            )
            lastError = nil
            return
        }
        if route == "speak" || route == "siri" || route == "voice" || path.contains("speak") || path.contains("voice") {
            // Background-first: Island + mic, no Speak sheet unless offline.
            toggleVoiceAIFromShortcut()
            return
        }
        if route == "eraser" || route == "radierer" || path.contains("eraser") || path.contains("radierer") {
            pendingTab = 1
            pendingOpenEraser = true
            return
        }
        if route == "livescreen" || route == "live-screen" || path.contains("livescreen") || path.contains("live-screen") {
            pendingTab = 2
            pendingOpenLiveScreen = true
            return
        }
        if route == "agent" || route == "noco-agent" || path.contains("/agent") {
            let goal = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "goal" || $0.name == "q" })?
                .value
            launchAgent(goal: goal)
            return
        }
        if route == "visionlive" || route == "vision-live" || route == "vision" || path.contains("visionlive") || path.contains("vision-live") {
            launchVisionLive()
            return
        }
        if route == "images" || route == "bildideen" || path.contains("images") || path.contains("bild") {
            let prompt = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "prompt" || $0.name == "q" })?
                .value
            launchImages(prompt: prompt)
            return
        }
        if route == "ask" || route == "chat" || path.contains("ask") {
            let draft = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "q" || $0.name == "draft" || $0.name == "text" })?
                .value
            if let draft, !draft.isEmpty {
                launchAsk(draft: draft)
            } else {
                pendingTab = 0
            }
            return
        }

        // Pairing deep links use IP/host that must not collide with route names.
        guard let link = PairingDeepLink.from(url: url) else { return }
        let linkHost = link.host.lowercased()
        let reserved = ["speak", "siri", "images", "bildideen", "agent", "vision", "ask", "chat", "eraser"]
        if reserved.contains(linkHost) { return }
        applyDeepLink(link)
        if let pin = link.pin, !pin.isEmpty {
            Task { await pair(host: link.host, port: link.port, pin: pin) }
        }
    }

    func handleQuickAction(_ type: String) {
        switch type {
        case "de.noco.nocoai.speak":
            toggleVoiceAIFromShortcut()
        case "de.noco.nocoai.images":
            launchImages(prompt: nil)
        case "de.noco.nocoai.agent":
            launchAgent(goal: nil)
        case "de.noco.nocoai.vision":
            launchVisionLive()
        default:
            break
        }
    }

    func launchImages(prompt: String?) {
        pendingTab = 1
        if let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            images.prompt = prompt
            images.genMode = .auto
        }
        NOCOLaunchBridge.pendingImages = false
        NOCOLaunchBridge.pendingImagePrompt = nil
        HapticService.soft()
    }

    func launchAgent(goal: String?) {
        pendingTab = 2
        pendingOpenAgent = true
        if let goal, !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pendingAgentDraft = goal
        }
        NOCOLaunchBridge.pendingAgent = false
        NOCOLaunchBridge.pendingAgentGoal = nil
        HapticService.soft()
    }

    func launchAsk(draft: String) {
        pendingTab = 0
        pendingChatDraft = draft
        chat.mode = .auto
        NOCOLaunchBridge.pendingAskDraft = nil
        HapticService.soft()
    }

    func launchVisionLive() {
        pendingTab = 2
        pendingOpenVisionLive = true
        speak.openUI()
        speak.visionCameraEnabled = true
        NOCOLaunchBridge.pendingVision = false
        HapticService.soft()
    }

    /// Shortcuts / Siri / Action Button / `nocoai://speak`.
    /// Honors `SpeakLaunchBridge.pendingToggle` for Action Button toggle semantics.
    /// Prefer background session (Island + audio) — Speak sheet only if offline / needed.
    func launchSpeakFromShortcut() {
        let wantsToggle = SpeakLaunchBridge.pendingToggle
        let backgroundOnly = SpeakLaunchBridge.preferBackgroundOnly || wantsToggle
        let alreadyActive = speak.isRunning || VoiceAISessionState.isActive

        // Instant silent stop — no companion wait, no farewell, no UI.
        if (wantsToggle && alreadyActive) || VoiceAISessionState.pendingStop {
            VoiceAISessionState.pendingStop = false
            SpeakLaunchBridge.clearPending()
            speak.showSpeakUI = false
            speak.exitVoiceAISilent()
            HapticService.soft()
            return
        }

        SpeakLaunchBridge.pendingStart = true
        Task { @MainActor in
            for _ in 0..<24 {
                if isPaired && isOnline { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
                await refreshStatus(showLoading: false)
            }
            guard SpeakLaunchBridge.pendingStart || SpeakLaunchBridge.pendingToggle else { return }
            let toggle = wantsToggle || SpeakLaunchBridge.pendingToggle
            if isOnline {
                let active = speak.isRunning || VoiceAISessionState.isActive
                if toggle, active {
                    speak.showSpeakUI = false
                    speak.exitVoiceAISilent()
                    SpeakLaunchBridge.clearPending()
                    HapticService.soft()
                } else if !active {
                    // Clean chat for Voice AI turns started from Shortcuts / Action Button.
                    openFreshChatOnEnter(force: true)
                    speak.showSpeakUI = false
                    speak.start()
                    SpeakLaunchBridge.clearPending()
                    // Keep sheet closed — Island is the surface.
                    speak.showSpeakUI = false
                    speak.ensureBackgroundPresence()
                    HapticService.success()
                } else {
                    SpeakLaunchBridge.clearPending()
                    speak.showSpeakUI = false
                    speak.ensureBackgroundPresence()
                }
            } else {
                SpeakLaunchBridge.clearPending()
                // Offline: only then surface the UI for recovery.
                speak.openUI()
                speak.statusLine = "PC offline — Companion starten, dann nochmal Shortcut"
            }
            _ = backgroundOnly
        }
    }

    func stopSpeakFromShortcut() {
        SpeakLaunchBridge.clearPending()
        VoiceAISessionState.pendingStop = false
        speak.showSpeakUI = false
        speak.exitVoiceAISilent()
    }

    /// Action Button / primary Shortcut: on ↔ off.
    func toggleVoiceAIFromShortcut() {
        if speak.isRunning || VoiceAISessionState.isActive || VoiceAISessionState.pendingStop {
            VoiceAISessionState.pendingStop = false
            SpeakLaunchBridge.clearPending()
            speak.showSpeakUI = false
            speak.exitVoiceAISilent()
            HapticService.soft()
            return
        }
        SpeakLaunchBridge.pendingToggle = true
        SpeakLaunchBridge.preferBackgroundOnly = true
        SpeakLaunchBridge.pendingStart = true
        launchSpeakFromShortcut()
    }

    func consumePendingSpeakLaunchIfNeeded() {
        if VoiceAISessionState.pendingStop {
            stopSpeakFromShortcut()
            return
        }
        guard SpeakLaunchBridge.pendingStart || SpeakLaunchBridge.pendingToggle else { return }
        launchSpeakFromShortcut()
    }

    func consumePendingSystemLaunches() {
        if let quick = NOCOQuickActionRouter.consume() {
            handleQuickAction(quick)
        }
        consumePendingSpeakLaunchIfNeeded()
        if NOCOLaunchBridge.pendingImages {
            launchImages(prompt: NOCOLaunchBridge.pendingImagePrompt)
        }
        if NOCOLaunchBridge.pendingAgent {
            launchAgent(goal: NOCOLaunchBridge.pendingAgentGoal)
        }
        if let draft = NOCOLaunchBridge.pendingAskDraft, !draft.isEmpty {
            launchAsk(draft: draft)
        }
        if NOCOLaunchBridge.pendingVision {
            launchVisionLive()
        }
    }

    func openImagesTab() {
        pendingTab = 1
    }

    /// Keep home-screen widget status fresh.
    func publishWidgetStatus() {
        let suite = UserDefaults(suiteName: CompanionCredentials.appGroupId)
        suite?.set(isOnline, forKey: "nocoai.widget.online")
        suite?.set(serverHost, forKey: "nocoai.host")
        suite?.synchronize()
        WidgetCenterReloader.reload()
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
        await pair(
            host: link.host,
            port: link.port,
            pin: pin,
            remoteHint: link.remoteHost ?? (HostSanitizer.isTailscaleIP(link.host) ? link.host : nil),
            lanHint: link.lanHost
        )
    }

    func refreshStatus(showLoading: Bool = false) async {
        guard let api else { return }
        if showLoading { isRefreshing = true }
        defer { if showLoading { isRefreshing = false } }

        // Prefer local path when away-session can return home.
        if activePath == .remote {
            await maybeOfferOrSwitchToLocal()
        }

        do {
            let started = Date()
            let newStatus = try await api.withTransientRetry(attempts: 2, baseDelayNanoseconds: 500_000_000) {
                try await api.fetchStatus()
            }
            let rttMs = Date().timeIntervalSince(started) * 1000
            status = newStatus.withMeasuredLatency(rttMs)
            // Companion reachable = online (independent of Ollama / AI readiness)
            let wasReconnecting = isReconnecting || !isOnline
            consecutiveFailures = 0
            isOnline = true
            lastStatusAt = Date()
            lastError = nil
            pathStatusLine = activePath.label
            if wasReconnecting {
                clearReconnectBanner(restored: true)
            }
            publishWidgetStatus()
            await loadFeatures()
            learnHosts(from: newStatus)
        } catch {
            if let err = error as? CompanionAPIError, case .remoteAccessDisabled = err {
                lastError = err.localizedDescription
                if activePath == .remote {
                    // Fall back to local if possible.
                    if await trySwitchToHost(preferredLocalHost, path: .local) {
                        return
                    }
                }
            }
            consecutiveFailures += 1
            if consecutiveFailures == 1 {
                beginReconnectBanner()
                // Immediate Tailscale try — don't wait for a second failure or a dialog.
                if activePath == .local, !preferredRemoteHost.isEmpty {
                    if await trySwitchToHost(preferredRemoteHost, path: .remote) {
                        return
                    }
                }
            }
            if consecutiveFailures >= offlineFailureThreshold {
                isOnline = false
                beginReconnectBanner()
                publishWidgetStatus()
                await handleOfflinePathRecovery()
            }
            if let err = error as? CompanionAPIError, case .unauthorized = err {
                disconnect()
                lastError = err.localizedDescription
            }
        }
    }

    /// Confirm Tailscale remote for this away stretch.
    func confirmRemoteConnection() async {
        showRemotePrompt = false
        remoteSessionApproved = true
        remotePromptSuppressedUntil = nil
        guard !preferredRemoteHost.isEmpty else {
            lastError = "Keine Tailscale-Adresse gespeichert. Zuhause erneut koppeln oder Remote-IP in den Einstellungen setzen."
            return
        }
        pathStatusLine = "Verbinde über Tailscale…"
        _ = await trySwitchToHost(preferredRemoteHost, path: .remote)
    }

    func declineRemoteConnection() {
        showRemotePrompt = false
        remoteSessionApproved = false
        remotePromptSuppressedUntil = Date().addingTimeInterval(15 * 60)
        pathStatusLine = "Nur lokale Verbindung"
    }

    func confirmLocalConnection() async {
        showLocalAvailablePrompt = false
        _ = await trySwitchToHost(preferredLocalHost, path: .local)
    }

    func declineLocalSwitch() {
        showLocalAvailablePrompt = false
    }

    func setAutoUseRemote(_ on: Bool) {
        autoUseRemote = on
        UserDefaults.standard.set(on, forKey: Keys.autoUseRemote)
    }

    func setAutoSwitchToLocal(_ on: Bool) {
        autoSwitchToLocal = on
        UserDefaults.standard.set(on, forKey: Keys.autoSwitchToLocal)
    }

    func setManualRemoteHost(_ host: String) {
        let cleaned = HostSanitizer.hostOnly(host)
        guard !cleaned.isEmpty else { return }
        remoteHost = cleaned
        UserDefaults.standard.set(cleaned, forKey: Keys.remoteHost)
    }

    private var preferredLocalHost: String {
        if !localHost.isEmpty { return localHost }
        if HostSanitizer.isPrivateLanIP(serverHost) { return serverHost }
        return localHost
    }

    private var preferredRemoteHost: String {
        if !remoteHost.isEmpty { return remoteHost }
        if HostSanitizer.isTailscaleIP(serverHost) { return serverHost }
        return remoteHost
    }

    private func rememberHosts(primary: String, remoteHint: String? = nil, lanHint: String? = nil) {
        if HostSanitizer.isTailscaleIP(primary) {
            remoteHost = primary
            activePath = .remote
            if let lan = lanHint?.trimmingCharacters(in: .whitespacesAndNewlines), !lan.isEmpty {
                localHost = HostSanitizer.hostOnly(lan)
            }
        } else {
            localHost = primary
            activePath = .local
        }
        if let hint = remoteHint?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty {
            remoteHost = HostSanitizer.hostOnly(hint)
        }
        if let lan = lanHint?.trimmingCharacters(in: .whitespacesAndNewlines), !lan.isEmpty,
           HostSanitizer.isPrivateLanIP(lan) || !HostSanitizer.isTailscaleIP(lan) {
            localHost = HostSanitizer.hostOnly(lan)
        }
        persistPathHosts()
    }

    private func persistPathHosts() {
        UserDefaults.standard.set(localHost, forKey: Keys.localHost)
        UserDefaults.standard.set(remoteHost, forKey: Keys.remoteHost)
        UserDefaults.standard.set(activePath.rawValue, forKey: Keys.activePath)
        UserDefaults.standard.set(serverHost, forKey: Keys.host)
    }

    private func learnHosts(from status: ServerStatus) {
        if let lan = status.lanHosts?.first(where: { HostSanitizer.isPrivateLanIP($0) })
            ?? status.hosts?.first(where: { HostSanitizer.isPrivateLanIP($0) }) {
            if localHost.isEmpty || localHost != lan {
                localHost = lan
            }
        }
        if let ts = status.tailscaleIP
            ?? status.tailscaleHosts?.first
            ?? status.hosts?.first(where: { HostSanitizer.isTailscaleIP($0) }) {
            remoteHost = ts
        }
        persistPathHosts()
    }

    private func handleOfflinePathRecovery() async {
        // 1) If on remote, try local first (home return / better path).
        if activePath == .remote, !preferredLocalHost.isEmpty {
            if await trySwitchToHost(preferredLocalHost, path: .local) {
                return
            }
        }

        // 2) Local offline → Tailscale automatically (simplest path).
        if activePath == .local, !preferredRemoteHost.isEmpty {
            remoteSessionApproved = true
            showRemotePrompt = false
            if await trySwitchToHost(preferredRemoteHost, path: .remote) {
                pathStatusLine = "Remote (Tailscale)"
                return
            }
            pathStatusLine = "Nicht erreichbar — PC: Remote starten · iPhone: Tailscale an"
            reconnectStatusLine = "Nicht erreichbar — PC: Remote starten · iPhone: Tailscale an"
        }
    }

    private func maybeOfferOrSwitchToLocal() async {
        guard !preferredLocalHost.isEmpty else { return }
        let now = Date()
        if let last = lastLocalProbeAt, now.timeIntervalSince(last) < 8 { return }
        lastLocalProbeAt = now
        guard await quickPing(host: preferredLocalHost) else { return }
        if autoSwitchToLocal {
            _ = await trySwitchToHost(preferredLocalHost, path: .local)
        } else {
            showLocalAvailablePrompt = true
            pathStatusLine = "Lokale Verbindung verfügbar."
        }
    }

    @discardableResult
    private func trySwitchToHost(_ host: String, path: ConnectionPathKind) async -> Bool {
        let cleaned = HostSanitizer.hostOnly(host)
        guard !cleaned.isEmpty else { return false }
        guard await quickPing(host: cleaned) else { return false }
        serverHost = cleaned
        activePath = path
        if path == .local {
            localHost = cleaned
            remoteSessionApproved = false
            showRemotePrompt = false
            showLocalAvailablePrompt = false
        } else {
            remoteHost = cleaned
            showRemotePrompt = false
        }
        persistPathHosts()
        prepareLocalNetworkAccess(host: cleaned, port: serverPort)
        rebuildAPI()
        CompanionCredentials.sync(
            host: serverHost,
            port: serverPort,
            token: token,
            deviceName: deviceName
        )
        consecutiveFailures = 0
        pathStatusLine = path.label
        do {
            guard let api else { return true }
            let started = Date()
            let newStatus = try await api.fetchStatus()
            status = newStatus.withMeasuredLatency(Date().timeIntervalSince(started) * 1000)
            isOnline = true
            lastStatusAt = Date()
            clearReconnectBanner(restored: true)
            publishWidgetStatus()
            HapticService.success()
            return true
        } catch {
            // Ping worked; status may still settle on next poll.
            isOnline = true
            clearReconnectBanner(restored: true)
            return true
        }
    }

    private func quickPing(host: String) async -> Bool {
        let cleaned = HostSanitizer.hostOnly(host)
        guard !cleaned.isEmpty,
              let url = URL(string: "http://\(cleaned):\(serverPort)/api/v1/ping") else { return false }
        var request = URLRequest(url: url)
        // Tailscale / mobile hops need more headroom than LAN.
        request.timeoutInterval = HostSanitizer.isTailscaleIP(cleaned) ? 5.5 : 2.4
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            if http.statusCode == 403 {
                return false
            }
            guard (200...299).contains(http.statusCode) else { return false }
            if let ping = try? JSONDecoder().decode(PingResponse.self, from: data) {
                return ping.isAlive
            }
            return true
        } catch {
            return false
        }
    }

    private func beginReconnectBanner() {
        isReconnecting = true
        if showRemotePrompt {
            reconnectStatusLine = "NOCO PC nicht im lokalen Netzwerk gefunden."
        } else {
            reconnectStatusLine = "Verbindung wird wiederhergestellt…"
        }
        chat.applyReconnectStatus(reconnectStatusLine)
        if speak.isRunning {
            speak.statusLine = reconnectStatusLine ?? "Verbindung wird wiederhergestellt…"
        }
    }

    private func clearReconnectBanner(restored: Bool) {
        guard isReconnecting || reconnectStatusLine != nil else { return }
        isReconnecting = false
        reconnectStatusLine = nil
        if restored {
            chat.clearReconnectStatus()
            if speak.isRunning, speak.statusLine.contains("Verbindung") || speak.statusLine.contains("Netzwerk") {
                speak.statusLine = "Wieder verbunden"
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
        isReconnecting = false
        reconnectStatusLine = nil
        showRemotePrompt = false
        showLocalAvailablePrompt = false
        remoteSessionApproved = false
        pathStatusLine = nil
        KeychainService.delete(account: Keys.token)
        CompanionCredentials.clear()
        UserDefaults.standard.set(false, forKey: "nocoai.onboardingDone")
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
                let offline = self?.isOnline != true || self?.isReconnecting == true
                // Faster polls while healing a drop; calm cadence when stable.
                let delay: UInt64 = offline ? 1_500_000_000 : 4_000_000_000
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }
}
