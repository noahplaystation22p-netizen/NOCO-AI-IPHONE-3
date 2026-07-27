import Foundation

@MainActor
final class ChatStore: ObservableObject {
    @Published var conversations: [ConversationSummary] = []
    @Published var messages: [ChatMessage] = []
    @Published var activeConversationId: String?
    @Published var mode: AIMode = .normal
    @Published var isSending = false
    @Published var isSyncActive = false
    @Published var lastSyncAt: Date?
    @Published var searchText = ""

    private var api: CompanionAPI?
    private var media: MediaURLBuilder?
    private var syncCursor: String?
    private var syncTask: Task<Void, Never>?

    var filteredConversations: [ConversationSummary] {
        guard !searchText.isEmpty else { return conversations }
        return conversations.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    func bind(api: CompanionAPI?, host: String, port: Int) {
        self.api = api
        self.media = MediaURLBuilder(host: host, port: port)
    }

    func startSyncLoop() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollSync()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    func stopSync() {
        syncTask?.cancel()
        syncTask = nil
    }

    func loadConversations() async {
        guard let api else { return }
        do {
            conversations = try await api.fetchConversations()
        } catch { /* offline */ }
    }

    func selectConversation(_ id: String) async {
        activeConversationId = id
        await loadMessages(for: id)
    }

    func newConversation() async {
        guard let api else { return }
        do {
            let created = try await api.createConversation(title: "Neuer Chat")
            activeConversationId = created.id
            messages = []
            await loadConversations()
        } catch { }
    }

    func loadMessages(for id: String) async {
        guard let api else { return }
        do {
            let detail = try await api.fetchConversation(id: id)
            messages = (detail.messages ?? []).map { dto in
                ChatMessage(
                    id: UUID(uuidString: dto.id) ?? UUID(),
                    role: dto.isUser ? .user : .assistant,
                    text: dto.content,
                    imageURL: media?.url(for: dto.mediaPath)
                )
            }
        } catch {
            messages = []
        }
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let api, !isSending else { return }

        if activeConversationId == nil {
            await newConversation()
        }
        guard let conversationId = activeConversationId else { return }

        isSending = true
        messages.append(ChatMessage(role: .user, text: trimmed))
        let assistant = ChatMessage(role: .assistant, text: "", isStreaming: true)
        messages.append(assistant)
        let assistantID = assistant.id
        HapticService.light()

        do {
            for try await chunk in api.streamChat(message: trimmed, conversationId: conversationId, mode: mode) {
                if let idx = messages.firstIndex(where: { $0.id == assistantID }) {
                    messages[idx].text += chunk
                }
            }
            if let idx = messages.firstIndex(where: { $0.id == assistantID }) {
                messages[idx].isStreaming = false
            }
            HapticService.success()
            await loadConversations()
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == assistantID }) {
                messages[idx].text = "Fehler: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
                messages[idx].isStreaming = false
            }
            HapticService.error()
        }
        isSending = false
    }

    func sendImage(_ data: Data, caption: String?) async {
        guard let api else { return }
        if activeConversationId == nil { await newConversation() }
        guard let conversationId = activeConversationId else { return }
        isSending = true
        defer { isSending = false }
        do {
            let dto = try await api.uploadVision(imageData: data, filename: "upload.jpg", message: caption, conversationId: conversationId)
            messages.append(ChatMessage(role: .user, text: caption ?? "Bild gesendet", imageURL: media?.url(for: dto.mediaPath)))
            if !dto.content.isEmpty {
                messages.append(ChatMessage(role: .assistant, text: dto.content))
            }
            HapticService.success()
        } catch {
            HapticService.error()
        }
    }

    func deleteConversation(_ id: String) async {
        guard let api else { return }
        try? await api.deleteConversation(id: id)
        if activeConversationId == id {
            activeConversationId = nil
            messages = []
        }
        await loadConversations()
    }

    private func pollSync() async {
        guard let api else { return }
        do {
            let res = try await api.fetchSyncEvents(since: syncCursor)
            syncCursor = res.cursor ?? syncCursor
            if !res.events.isEmpty {
                isSyncActive = true
                lastSyncAt = .now
                for event in res.events {
                    await handle(event)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.isSyncActive = false
                }
            }
        } catch { }
    }

    private func handle(_ event: SyncEvent) async {
        switch event.type {
        case "message.added":
            if let cid = event.conversationId, cid == activeConversationId, let dto = event.message {
                let msg = ChatMessage(
                    id: UUID(uuidString: dto.id) ?? UUID(),
                    role: dto.isUser ? .user : .assistant,
                    text: dto.content,
                    imageURL: media?.url(for: dto.mediaPath)
                )
                if !messages.contains(where: { $0.text == msg.text && $0.role == msg.role }) {
                    messages.append(msg)
                }
            }
            await loadConversations()
        case "conversation.updated":
            await loadConversations()
        default:
            break
        }
    }
}
