import Foundation

struct GeneratedImageItem: Identifiable, Equatable {
    let id: String
    let prompt: String
    let url: URL?
    let createdAt: Date
}

@MainActor
final class ImageStore: ObservableObject {
    @Published var prompt = ""
    @Published var progress: Double = 0
    @Published var isGenerating = false
    @Published var statusText = ""
    @Published var gallery: [GeneratedImageItem] = []
    @Published var lastImageURL: URL?

    private var api: CompanionAPI?
    private var media: MediaURLBuilder?
    private var currentJobId: String?

    func bind(api: CompanionAPI?, host: String, port: Int) {
        self.api = api
        self.media = MediaURLBuilder(host: host, port: port)
    }

    func loadFromConversations(_ conversations: [ConversationSummary], api: CompanionAPI?) async {
        guard let api, let media else { return }
        var items: [GeneratedImageItem] = []
        for convo in conversations where convo.type == "generated-image" || convo.title.lowercased().contains("bild") {
            if let detail = try? await api.fetchConversation(id: convo.id) {
                for msg in detail.messages ?? [] where msg.isGeneratedImage || msg.mediaPath != nil {
                    items.append(GeneratedImageItem(
                        id: msg.id,
                        prompt: msg.content,
                        url: media.url(for: msg.mediaPath ?? msg.content),
                        createdAt: .now
                    ))
                }
            }
        }
        gallery = items
    }

    func generate(conversationId: String? = nil) async {
        guard let api, !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isGenerating = true
        progress = 0
        statusText = "Starte Generierung…"
        defer { isGenerating = false }

        do {
            let res = try await api.generateImage(prompt: prompt, conversationId: conversationId)
            currentJobId = res.jobId
            if let path = res.imageUrl, let url = media?.url(for: path) {
                finish(url: url, prompt: prompt)
                return
            }
            await pollProgress(prompt: prompt)
        } catch {
            statusText = (error as? LocalizedError)?.errorDescription ?? "Fehler"
            HapticService.error()
        }
    }

    private func pollProgress(prompt: String) async {
        guard let api else { return }
        for _ in 0..<120 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let prog = try? await api.imageProgress(jobId: currentJobId) else { continue }
            progress = prog.value / 100.0
            statusText = prog.status ?? "Generiere… \(Int(prog.value))%"
            if prog.done == true || prog.imageUrl != nil {
                if let url = media?.url(for: prog.imageUrl) {
                    finish(url: url, prompt: prompt)
                }
                return
            }
        }
        statusText = "Zeitüberschreitung"
    }

    private func finish(url: URL, prompt: String) {
        lastImageURL = url
        progress = 1
        statusText = "Fertig ✓"
        gallery.insert(GeneratedImageItem(id: UUID().uuidString, prompt: prompt, url: url, createdAt: .now), at: 0)
        HapticService.success()
    }
}
