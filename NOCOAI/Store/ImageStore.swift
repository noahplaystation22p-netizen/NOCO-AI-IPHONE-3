import Foundation
import Photos
import UIKit

struct GeneratedImageItem: Identifiable, Equatable {
    let id: String
    let prompt: String
    let url: URL?
    let localData: Data?
    let createdAt: Date

    init(id: String = UUID().uuidString, prompt: String, url: URL? = nil, localData: Data? = nil, createdAt: Date = .now) {
        self.id = id
        self.prompt = prompt
        self.url = url
        self.localData = localData
        self.createdAt = createdAt
    }
}

@MainActor
final class ImageStore: ObservableObject {
    @Published var prompt = ""
    @Published var progress: Double = 0
    @Published var isGenerating = false
    @Published var statusText = ""
    @Published var insightText = ""
    @Published var etaSeconds: Int?
    @Published var gallery: [GeneratedImageItem] = []
    @Published var lastImageURL: URL?
    @Published var lastImageData: Data?
    @Published var lastPrompt = ""
    @Published var saveMessage: String?
    @Published var phase: Phase = .idle
    @Published var isPreparingEngine = false
    @Published var engineStatusText = ""
    /// Flash / Think / Auto — maps to SD steps+size (same engine).
    @Published var genMode: ImageGenMode = .auto
    @Published private(set) var lastResolvedMode: ImageGenMode?

    enum Phase: Equatable {
        case idle
        case preparing
        case rendering
        case finishing
        case done
        case error
    }

    private var api: CompanionAPI?
    private var media: MediaURLBuilder?
    private var pollTask: Task<Void, Never>?
    private var insightTask: Task<Void, Never>?
    private var cancelled = false
    private var startedAt: Date?
    private var lastHapticBucket = -1

    private var sawRealProgress = false

    private let insights = [
        "Motiv nimmt Form an…",
        "Licht & Farbe entstehen…",
        "Details werden gezeichnet…",
        "Noch einen Moment…",
        "Feinschliff…",
        "Gleich fertig…"
    ]

    private let thinkInsights = [
        "Höhere Qualität, mehr Schritte…",
        "Details entstehen…",
        "Braucht etwas länger — das ist normal…",
        "Feinschliff…",
        "Noch einen Moment…",
        "Gleich fertig…"
    ]

    private var generateTask: Task<Void, Never>?
    /// Called when a real image finished (conversationId from PC, if any).
    var onGenerationFinished: ((String?, String, URL?, Data?) -> Void)?

    func bind(api: CompanionAPI?, host: String, port: Int) {
        self.api = api
        self.media = MediaURLBuilder(host: host, port: port)
    }

    /// Fire-and-forget so leaving the screen / app does not cancel generation.
    /// Always creates a dedicated Bild-chat on the PC (nil conversationId).
    func startGenerate(conversationId: String? = nil) {
        guard !isGenerating else { return }
        generateTask = Task { [weak self] in
            // Prefer a fresh Bild-chat rather than polluting the active chat
            await self?.generate(conversationId: nil)
        }
    }

    func loadFromConversations(_ conversations: [ConversationSummary], api: CompanionAPI?) async {
        guard let api, let media else { return }
        var items: [GeneratedImageItem] = []
        // Prefer Bild-chats, but also scan recent threads so PC/mobile images show up
        let preferred = conversations.filter {
            $0.type == "generated-image" ||
            $0.title.lowercased().contains("bild") ||
            $0.title.lowercased().contains("image")
        }
        var scan = preferred
        for c in conversations where !scan.contains(where: { $0.id == c.id }) {
            scan.append(c)
            if scan.count >= 40 { break }
        }
        for convo in scan {
            guard let detail = try? await api.fetchConversation(id: convo.id) else { continue }
            for msg in detail.messages ?? [] {
                let isImage = msg.isGeneratedImage || (msg.resolvedMediaPath?.contains("/media/") == true)
                guard isImage, let path = msg.resolvedMediaPath else { continue }
                items.append(GeneratedImageItem(
                    id: msg.id,
                    prompt: msg.content,
                    url: media.url(for: path),
                    createdAt: .now
                ))
            }
        }
        // Keep newest first, unique by id; preserve any in-memory local items without server id clash
        var seen = Set<String>()
        var merged = items.filter { seen.insert($0.id).inserted }
        for local in gallery where local.localData != nil {
            if !merged.contains(where: { $0.url == local.url && local.url != nil }) {
                merged.insert(local, at: 0)
            }
        }
        gallery = merged
    }

    func generate(conversationId: String? = nil) async {
        guard let api else { return }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating else { return }

        cancelled = false
        isGenerating = true
        phase = .preparing
        progress = 0.02
        let resolved = genMode.resolved(for: trimmed)
        lastResolvedMode = resolved
        let params = resolved.engineParams
        statusText = resolved == .think
            ? "Erstelle Bild in hoher Qualität…"
            : "Erstelle Bild…"
        insightText = resolved == .think ? thinkInsights[0] : insights[0]
        etaSeconds = resolved == .think ? 420 : 200
        startedAt = .now
        sawRealProgress = false
        lastHapticBucket = -1
        saveMessage = nil
        lastPrompt = trimmed
        HapticService.medium()
        HapticService.rigid()

        _ = await AppNotificationService.requestAuthorizationIfNeeded()
        ImageBackgroundKeeper.shared.begin()
        ImageLiveActivityManager.start(prompt: "\(resolved.emoji) \(trimmed)")
        startInsightLoop()
        startProgressPolling()

        defer {
            pollTask?.cancel()
            pollTask = nil
            insightTask?.cancel()
            insightTask = nil
            isGenerating = false
            ImageBackgroundKeeper.shared.end(preserveAudioSession: true)
        }

        do {
            let res = try await api.generateImage(
                prompt: trimmed,
                conversationId: conversationId,
                width: params.width,
                height: params.height,
                steps: params.steps
            )
            guard !cancelled else {
                phase = .idle
                statusText = "Abgebrochen"
                ImageLiveActivityManager.end(immediate: true)
                return
            }
            phase = .finishing
            progress = 0.98
            statusText = "Bild kommt an…"
            pushImageLiveActivity(force: true)

            if let b64 = res.imageBase64, let data = Data(base64Encoded: b64) {
                finish(
                    data: data,
                    url: media?.url(for: res.resolvedPath),
                    prompt: trimmed,
                    conversationId: res.conversationId
                )
                return
            }
            if let path = res.resolvedPath, let url = media?.url(for: path) {
                if let data = try? await download(url: url) {
                    finish(data: data, url: url, prompt: trimmed, conversationId: res.conversationId)
                } else {
                    finish(data: nil, url: url, prompt: trimmed, conversationId: res.conversationId)
                }
                return
            }
            phase = .error
            statusText = "Kein Bild in der Antwort"
            HapticService.error()
            ImageLiveActivityManager.fail(statusText)
            await AppNotificationService.notifyImageFailed(statusText)
        } catch {
            guard !cancelled else {
                phase = .idle
                statusText = "Abgebrochen"
                ImageLiveActivityManager.end(immediate: true)
                return
            }
            phase = .error
            statusText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            HapticService.error()
            ImageLiveActivityManager.fail(statusText)
            await AppNotificationService.notifyImageFailed(statusText)
        }
    }

    /// Call when app enters background during generation.
    func handleDidEnterBackground() {
        guard isGenerating else { return }
        ImageBackgroundKeeper.shared.begin()
        if !ImageLiveActivityManager.isActive {
            ImageLiveActivityManager.start(prompt: lastPrompt.isEmpty ? prompt : lastPrompt)
        }
        pushImageLiveActivity(force: true)
    }

    /// Call when returning to foreground.
    func handleDidBecomeActive() {
        AppNotificationService.clearBadge()
        if isGenerating {
            ImageBackgroundKeeper.shared.begin()
        }
    }

    func cancel() async {
        guard isGenerating else { return }
        cancelled = true
        statusText = "Wird abgebrochen…"
        phase = .idle
        generateTask?.cancel()
        generateTask = nil
        try? await api?.interruptImage()
        pollTask?.cancel()
        insightTask?.cancel()
        isGenerating = false
        progress = 0
        etaSeconds = nil
        ImageBackgroundKeeper.shared.end(preserveAudioSession: true)
        ImageLiveActivityManager.end(immediate: true)
        AppNotificationService.clearRunningNotification()
        HapticService.soft()
        statusText = "Abgebrochen"
    }

    /// Magischer Radierer result → gallery.
    func ingestEditedImage(prompt: String, localData: Data, path: String?) {
        let url = media?.url(for: path)
        let item = GeneratedImageItem(
            prompt: "🪄 \(prompt)",
            url: url,
            localData: localData
        )
        gallery.insert(item, at: 0)
        lastImageData = localData
        lastImageURL = url
        lastPrompt = prompt
        phase = .done
        statusText = "Radierer fertig"
    }

    /// Start / warm Stable Diffusion on the PC (same engine as Bildidee + Radierer).
    func prepareEngine() async -> Bool {
        guard let api, !isPreparingEngine else { return false }
        isPreparingEngine = true
        engineStatusText = "Bilder-Engine startet…"
        statusText = engineStatusText
        defer { isPreparingEngine = false }
        do {
            let res = try await api.prepareImageEngine()
            engineStatusText = res.displayMessage
            statusText = engineStatusText
            if res.isReady {
                HapticService.success()
                return true
            }
            HapticService.warning()
            return false
        } catch {
            engineStatusText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusText = engineStatusText
            HapticService.error()
            return false
        }
    }

    /// Soft SD progress for eraser theater (0…1).
    func peekProgress() async -> Double {
        guard let api else { return 0 }
        return (try? await api.imageProgress())?.normalizedProgress ?? 0
    }

    func runInpaint(
        prompt: String,
        imageJPEG: Data,
        maskPNG: Data,
        denoisingStrength: Double = 0.82
    ) async throws -> ImageGenerateResponse {
        guard let api else {
            throw CompanionAPIError.unreachable
        }
        return try await api.inpaintImage(
            prompt: prompt,
            imageJPEG: imageJPEG,
            maskPNG: maskPNG,
            conversationId: nil,
            denoisingStrength: denoisingStrength,
            steps: denoisingStrength >= 0.7 ? 16 : 12
        )
    }

    func saveLastToPhotos() async {
        let data: Data?
        if let lastImageData {
            data = lastImageData
        } else if let url = lastImageURL {
            data = try? await download(url: url)
        } else {
            data = nil
        }
        guard let data else {
            saveMessage = "Kein Bild zum Speichern"
            return
        }
        do {
            try await savePhoto(data: data)
            saveMessage = "In Fotos gespeichert ✓"
            HapticService.success()
        } catch {
            saveMessage = "Speichern fehlgeschlagen — bitte Zugriff erlauben"
            HapticService.error()
        }
    }

    func saveItemToPhotos(_ item: GeneratedImageItem) async {
        let data: Data?
        if let local = item.localData {
            data = local
        } else if let url = item.url {
            data = try? await download(url: url)
        } else {
            data = nil
        }
        guard let data else {
            saveMessage = "Bild nicht ladbar"
            return
        }
        do {
            try await savePhoto(data: data)
            saveMessage = "In Fotos gespeichert ✓"
            HapticService.success()
        } catch {
            saveMessage = "Speichern fehlgeschlagen"
            HapticService.error()
        }
    }

    // MARK: - Private

    private func startProgressPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tickProgress()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    private func startInsightLoop() {
        insightTask?.cancel()
        insightTask = Task { [weak self] in
            var i = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_500_000_000)
                guard let self, self.isGenerating else { return }
                let pool = self.lastResolvedMode == .think ? self.thinkInsights : self.insights
                i = (i + 1) % pool.count
                self.insightText = pool[i]
                self.pushImageLiveActivity(force: false)
            }
        }
    }

    private func tickProgress() async {
        guard let api, isGenerating, !cancelled else { return }
        do {
            let prog = try await api.imageProgress()
            let next = prog.normalizedProgress
            if next > 0.01 {
                sawRealProgress = true
                phase = .rendering
            }
            if next > progress + 0.012 {
                progress = next
            } else if !sawRealProgress {
                // Soft time-based fill while SD cold-starts (up to ~70% over 3 min)
                let elapsed = Date().timeIntervalSince(startedAt ?? .now)
                let soft = min(0.7, elapsed / 180.0)
                progress = max(progress, soft)
                phase = elapsed < 25 ? .preparing : .rendering
            }

            let bucket = Int(progress * 4) // 0,1,2,3 at 0/25/50/75%
            if bucket > lastHapticBucket, bucket >= 1 {
                lastHapticBucket = bucket
                HapticService.selection()
            }

            if let eta = prog.etaRelative, eta > 0 {
                etaSeconds = Int(eta.rounded())
            } else if let step = prog.state?.samplingStep, let steps = prog.state?.samplingSteps, steps > 0, step < steps {
                let remaining = steps - step
                etaSeconds = remaining * 18
            } else if !sawRealProgress {
                let elapsed = Date().timeIntervalSince(startedAt ?? .now)
                etaSeconds = max(30, Int(240 - elapsed))
            }

            statusText = Self.friendlyProgressStatus(
                progress: prog,
                phase: phase,
                percent: Int(progress * 100),
                isThink: lastResolvedMode == .think
            )
            pushImageLiveActivity(force: false)
        } catch {
            // Keep animating through transient poll errors
        }
    }

    /// Prefer clear German status — never surface raw SD English chatter.
    private static func friendlyProgressStatus(
        progress prog: ImageProgressResponse,
        phase: Phase,
        percent: Int,
        isThink _: Bool
    ) -> String {
        if let step = prog.state?.samplingStep, let steps = prog.state?.samplingSteps, steps > 0 {
            return "Erstellt Bild… Schritt \(step)/\(steps)"
        }
        if let raw = prog.textinfo?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let low = raw.lowercased()
            // Drop noisy / nonsensical engine strings
            let junk = ["more than", "no more", "waiting", "loading model", "model loaded", "error"]
            if !junk.contains(where: { low.contains($0) }), raw.count < 60, !raw.contains("http") {
                if low.hasPrefix("step ") || low.contains("sampling") {
                    return "Erstellt Bild… \(percent)%"
                }
            }
        }
        if phase == .preparing {
            return "Startet…"
        }
        return "Erstellt Bild… \(percent)%"
    }

    /// Shared progress copy for in-chat image generation.
    static func chatFriendlyProgress(_ prog: ImageProgressResponse) -> String {
        friendlyProgressStatus(
            progress: prog,
            phase: .rendering,
            percent: Int(prog.normalizedProgress * 100),
            isThink: false
        )
    }

    private func pushImageLiveActivity(force: Bool) {
        guard isGenerating else { return }
        let livePhase: ImageActivityPhase
        switch phase {
        case .preparing: livePhase = .preparing
        case .rendering: livePhase = .rendering
        case .finishing: livePhase = .finishing
        case .done: livePhase = .done
        case .error: livePhase = .error
        case .idle: livePhase = .preparing
        }
        ImageLiveActivityManager.update(
            progress: progress,
            status: livePhase.title,
            insight: insightText.isEmpty ? statusText : insightText,
            etaSeconds: etaSeconds,
            phase: livePhase,
            force: force
        )
    }

    private func finish(data: Data?, url: URL?, prompt: String, conversationId: String?) {
        lastImageData = data
        lastImageURL = url
        lastPrompt = prompt
        progress = 1
        phase = .done
        statusText = "Fertig ✓"
        insightText = "Bildidee bereit"
        etaSeconds = nil
        let item = GeneratedImageItem(prompt: prompt, url: url, localData: data)
        if !gallery.contains(where: { $0.id == item.id }) {
            gallery.insert(item, at: 0)
        }
        HapticService.success()
        ImageLiveActivityManager.complete(prompt: prompt)
        onGenerationFinished?(conversationId, prompt, url, data)
        Task {
            // Only after the image bytes/URL are actually ready
            await AppNotificationService.notifyImageReady(prompt: prompt)
        }
    }

    /// Add a chat-generated image to the gallery without switching tabs.
    func ingestFromChat(prompt: String, url: URL?, data: Data?) {
        lastImageData = data
        lastImageURL = url
        lastPrompt = prompt
        let item = GeneratedImageItem(prompt: prompt, url: url, localData: data)
        gallery.insert(item, at: 0)
    }

    private func download(url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw CompanionAPIError.server("Bild-Download fehlgeschlagen (\(http.statusCode))")
        }
        return data
    }

    private func savePhoto(data: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw CompanionAPIError.server("Kein Zugriff auf Fotos")
        }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }
    }
}
