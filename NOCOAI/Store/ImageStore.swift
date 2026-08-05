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
    private var sawRealProgress = false

    private let insights = [
        "PC bereitet Stable Diffusion vor…",
        "Motiv nimmt Form an…",
        "Licht & Farbe entstehen…",
        "Details werden gezeichnet…",
        "Feinschliff auf dem PC…",
        "Noch einen Moment — CPU rechnet…"
    ]

    private var generateTask: Task<Void, Never>?

    func bind(api: CompanionAPI?, host: String, port: Int) {
        self.api = api
        self.media = MediaURLBuilder(host: host, port: port)
    }

    /// Fire-and-forget so leaving the screen / app does not cancel generation.
    func startGenerate(conversationId: String? = nil) {
        guard !isGenerating else { return }
        generateTask = Task { [weak self] in
            await self?.generate(conversationId: conversationId)
        }
    }

    func loadFromConversations(_ conversations: [ConversationSummary], api: CompanionAPI?) async {
        guard let api, let media else { return }
        var items: [GeneratedImageItem] = []
        let candidates = conversations.filter {
            $0.type == "generated-image" ||
            $0.title.lowercased().contains("bild") ||
            $0.title.lowercased().contains("image")
        }
        let scan = candidates.isEmpty ? Array(conversations.prefix(12)) : candidates
        for convo in scan {
            guard let detail = try? await api.fetchConversation(id: convo.id) else { continue }
            for msg in detail.messages ?? [] where msg.isGeneratedImage || msg.resolvedMediaPath != nil {
                guard msg.isGeneratedImage || (msg.resolvedMediaPath?.contains("/media/") == true) else { continue }
                items.append(GeneratedImageItem(
                    id: msg.id,
                    prompt: msg.content,
                    url: media.url(for: msg.resolvedMediaPath),
                    createdAt: .now
                ))
            }
        }
        // Keep newest first, unique by id
        var seen = Set<String>()
        gallery = items.filter { seen.insert($0.id).inserted }
    }

    func generate(conversationId: String? = nil) async {
        guard let api else { return }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating else { return }

        cancelled = false
        isGenerating = true
        phase = .preparing
        progress = 0.02
        statusText = "Sende an PC…"
        insightText = insights[0]
        etaSeconds = 240
        startedAt = .now
        sawRealProgress = false
        saveMessage = nil
        lastPrompt = trimmed
        HapticService.medium()

        _ = await AppNotificationService.requestAuthorizationIfNeeded()
        ImageBackgroundKeeper.shared.begin()
        startInsightLoop()
        startProgressPolling()

        defer {
            pollTask?.cancel()
            pollTask = nil
            insightTask?.cancel()
            insightTask = nil
            isGenerating = false
            ImageBackgroundKeeper.shared.end()
        }

        do {
            let res = try await api.generateImage(prompt: trimmed, conversationId: conversationId)
            guard !cancelled else {
                phase = .idle
                statusText = "Abgebrochen"
                return
            }
            phase = .finishing
            progress = 0.98
            statusText = "Bild kommt an…"

            if let b64 = res.imageBase64, let data = Data(base64Encoded: b64) {
                finish(data: data, url: media?.url(for: res.resolvedPath), prompt: trimmed)
                return
            }
            if let path = res.resolvedPath, let url = media?.url(for: path) {
                if let data = try? await download(url: url) {
                    finish(data: data, url: url, prompt: trimmed)
                } else {
                    finish(data: nil, url: url, prompt: trimmed)
                }
                return
            }
            phase = .error
            statusText = "Kein Bild in der Antwort"
            HapticService.error()
            await AppNotificationService.notifyImageFailed(statusText)
        } catch {
            guard !cancelled else {
                phase = .idle
                statusText = "Abgebrochen"
                return
            }
            phase = .error
            statusText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            HapticService.error()
            await AppNotificationService.notifyImageFailed(statusText)
        }
    }

    /// Call when app enters background during generation.
    func handleDidEnterBackground() {
        guard isGenerating else { return }
        ImageBackgroundKeeper.shared.begin()
        Task {
            await AppNotificationService.notifyImageStarted(prompt: lastPrompt.isEmpty ? prompt : lastPrompt)
        }
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
        ImageBackgroundKeeper.shared.end()
        AppNotificationService.clearRunningNotification()
        HapticService.soft()
        statusText = "Abgebrochen"
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
                try? await Task.sleep(nanoseconds: 1_200_000_000)
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
                i = (i + 1) % self.insights.count
                self.insightText = self.insights[i]
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
            if next > progress {
                progress = next
            } else if !sawRealProgress {
                // Soft time-based fill while SD cold-starts (up to ~70% over 3 min)
                let elapsed = Date().timeIntervalSince(startedAt ?? .now)
                let soft = min(0.7, elapsed / 180.0)
                progress = max(progress, soft)
                phase = elapsed < 25 ? .preparing : .rendering
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

            if let step = prog.stepLabel {
                statusText = step
            } else if let info = prog.textinfo, !info.isEmpty {
                statusText = info
            } else if phase == .preparing {
                statusText = "Engine startet…"
            } else {
                statusText = "Generiere… \(Int(progress * 100))%"
            }
        } catch {
            // Keep animating through transient poll errors
        }
    }

    private func finish(data: Data?, url: URL?, prompt: String) {
        lastImageData = data
        lastImageURL = url
        lastPrompt = prompt
        progress = 1
        phase = .done
        statusText = "Fertig ✓"
        insightText = "Bildidee bereit"
        etaSeconds = nil
        let item = GeneratedImageItem(prompt: prompt, url: url, localData: data)
        gallery.insert(item, at: 0)
        HapticService.success()
        Task {
            await AppNotificationService.notifyImageReady(prompt: prompt)
        }
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
