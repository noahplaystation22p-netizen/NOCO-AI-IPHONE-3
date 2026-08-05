import Foundation

@MainActor
final class ChatStore: ObservableObject {
    @Published var conversations: [ConversationSummary] = []
    @Published var messages: [ChatMessage] = []
    @Published var activeConversationId: String?
    @Published var mode: AIMode = .auto
    @Published var isSending = false
    @Published var isSyncActive = false
    @Published var lastSyncAt: Date?
    @Published var searchText = ""
    @Published var lastError: String?

    private var api: CompanionAPI?
    private var media: MediaURLBuilder?
    private var syncCursor: String?
    private var syncTask: Task<Void, Never>?

    private let syncIntervalNs: UInt64 = 1_000_000_000

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
                try? await Task.sleep(nanoseconds: self?.syncIntervalNs ?? 2_000_000_000)
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
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription
        }
    }

    func selectConversation(_ id: String) async {
        activeConversationId = id
        persistActiveConversation()
        await loadMessages(for: id)
        HapticService.selection()
    }

    func newConversation() async -> String? {
        guard let api else { return nil }
        do {
            let created = try await api.createConversation(title: "Neuer Chat")
            guard let id = created.resolvedId else { return nil }
            activeConversationId = id
            persistActiveConversation()
            messages = []
            await loadConversations()
            HapticService.medium()
            return id
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription
            return nil
        }
    }

    func loadMessages(for id: String) async {
        guard let api else { return }
        do {
            let detail = try await api.fetchConversation(id: id)
            let serverMessages = mapMessages(detail.messages ?? [])
            if isSending {
                messages = mergeWithLocal(server: serverMessages)
            } else {
                messages = serverMessages
            }
        } catch {
            if !isSending { messages = [] }
        }
    }

    func send(_ text: String) async {
        _ = await sendAndReturnReply(text, modeOverride: nil)
    }

    /// Sends a chat message and returns the final assistant text (for voice TTS).
    @discardableResult
    func sendAndReturnReply(_ text: String, modeOverride: AIMode? = nil) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let api, !isSending else { return nil }

        HapticService.prepare()
        HapticService.send()

        isSending = true
        lastError = nil
        let sendMode = modeOverride ?? mode

        let userMessage = ChatMessage(role: .user, text: trimmed)
        messages.append(userMessage)
        let assistant = ChatMessage(role: .assistant, text: "", isStreaming: true)
        messages.append(assistant)
        let assistantID = assistant.id

        let isStartingNewChat = activeConversationId == nil
        var conversationId = activeConversationId
        var reply: String?

        do {
            for try await chunk in api.streamChatV2(message: trimmed, conversationId: conversationId, mode: sendMode) {
                if let cid = chunk.conversationId, !cid.isEmpty {
                    conversationId = cid
                    activeConversationId = cid
                    persistActiveConversation()
                }
                if let text = chunk.content, !text.isEmpty {
                    if let idx = messages.firstIndex(where: { $0.id == assistantID }) {
                        messages[idx].text += text
                    }
                    HapticService.streamTick()
                }
                if chunk.done == true { break }
            }

            if let idx = messages.firstIndex(where: { $0.id == assistantID }) {
                messages[idx].isStreaming = false
                let final = messages[idx].text.trimmingCharacters(in: .whitespacesAndNewlines)
                reply = final.isEmpty ? nil : final
            }

            await resolveConversationId(conversationId, preferLatest: isStartingNewChat)
            await syncFromServer()
            HapticService.success()
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == assistantID }) {
                messages[idx].text = "Fehler: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
                messages[idx].isStreaming = false
            }
            lastError = (error as? LocalizedError)?.errorDescription
            HapticService.error()
            reply = nil
        }

        isSending = false
        return reply
    }

    func sendImage(_ data: Data, caption: String?) async {
        guard let api else { return }

        HapticService.prepare()
        HapticService.rigid()

        let isStartingNewChat = activeConversationId == nil

        let userText = caption?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? caption!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "Bild"

        let userMessage = ChatMessage(role: .user, text: userText, localImageData: data)
        messages.append(userMessage)

        isSending = true
        lastError = nil
        defer { isSending = false }

        do {
            let result = try await api.uploadVisionImage(
                imageData: data,
                filename: "upload.jpg",
                message: caption,
                conversationId: activeConversationId
            )

            if let cid = result.conversationId, !cid.isEmpty {
                activeConversationId = cid
                persistActiveConversation()
            }

            if let assistant = result.asAssistantMessage() {
                messages.append(mapMessage(assistant))
                HapticService.messageReceived()
            }

            await resolveConversationId(activeConversationId, preferLatest: isStartingNewChat)
            await syncFromServer()
            HapticService.success()
        } catch {
            messages.append(ChatMessage(role: .assistant, text: "Bild-Upload fehlgeschlagen: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"))
            lastError = (error as? LocalizedError)?.errorDescription
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
        HapticService.medium()
    }

    private func resolveConversationId(_ known: String?, preferLatest: Bool = false) async {
        if let known, !known.isEmpty {
            activeConversationId = known
            persistActiveConversation()
            return
        }
        await loadConversations()
        if preferLatest, let latest = conversations.sorted(by: {
            ($0.updatedAt ?? "") > ($1.updatedAt ?? "")
        }).first {
            activeConversationId = latest.id
            persistActiveConversation()
            return
        }
        if activeConversationId == nil, let latest = conversations.first {
            activeConversationId = latest.id
            persistActiveConversation()
        }
    }

    private func syncFromServer() async {
        await pollSync()
        if let id = activeConversationId {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await loadMessages(for: id)
        }
        await loadConversations()
    }

    private func pollSync() async {
        guard let api else { return }
        do {
            let res = try await api.fetchSyncEvents(since: syncCursor)
            syncCursor = res.cursor ?? syncCursor
            guard !res.events.isEmpty else { return }

            isSyncActive = true
            lastSyncAt = .now

            for event in res.events {
                await handle(event)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.isSyncActive = false
            }
        } catch { }
    }

    private func handle(_ event: SyncEvent) async {
        switch event.type {
        case "message.added", "message.created":
            if let cid = event.conversationId {
                if activeConversationId == nil { activeConversationId = cid }
                if cid == activeConversationId {
                    await loadMessages(for: cid)
                    HapticService.messageReceived()
                }
            }
            await loadConversations()
        case "conversation.updated", "conversation.created":
            await loadConversations()
            if activeConversationId == nil, let cid = event.conversationId {
                activeConversationId = cid
                await loadMessages(for: cid)
            } else if let cid = activeConversationId {
                await loadMessages(for: cid)
            }
        default:
            break
        }
    }

    private func mapMessages(_ dtos: [ConversationMessageDTO]) -> [ChatMessage] {
        dtos.map(mapMessage)
    }

    private func mapMessage(_ dto: ConversationMessageDTO) -> ChatMessage {
        ChatMessage(
            id: stableUUID(dto.id),
            serverId: dto.id,
            role: dto.isUser ? .user : .assistant,
            text: dto.content,
            imageURL: media?.url(for: dto.resolvedMediaPath)
        )
    }

    private func stableUUID(_ serverId: String) -> UUID {
        UUID(uuidString: serverId) ?? UUID()
    }

    private func persistActiveConversation() {
        if let id = activeConversationId {
            UserDefaults.standard.set(id, forKey: "nocoai.activeConversation")
        }
    }

    func restoreSession() {
        if let saved = UserDefaults.standard.string(forKey: "nocoai.activeConversation") {
            activeConversationId = saved
        }
    }

    private func mergeWithLocal(server: [ChatMessage]) -> [ChatMessage] {
        guard let streaming = messages.last(where: { $0.isStreaming }) else { return server }
        var merged = server
        if !merged.contains(where: { $0.serverId == streaming.serverId && streaming.serverId != nil }) {
            merged.append(streaming)
        }
        return merged
    }
}
