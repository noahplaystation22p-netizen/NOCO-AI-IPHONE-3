import UIKit
import Foundation

@MainActor
final class ChatStore: ObservableObject {
    @Published var conversations: [ConversationSummary] = []
    @Published var messages: [ChatMessage] = []
    @Published var activeConversationId: String?
    @Published var mode: AIMode = .auto
    @Published var isSending = false
    private var sendTask: Task<Void, Never>?
    @Published var isSyncActive = false
    @Published var lastSyncAt: Date?
    @Published var searchText = ""
    @Published var lastError: String?
    @Published var peerTyping = false
    @Published var peerTypingDraft: String?
    @Published var chatLimitReached = false
    @Published var isCompacting = false
    private let softMessageLimit = 36
    private let keepAfterCompact = 30
    /// Vision replies can flash then vanish when sync reloads before the PC has persisted them.
    private var stickyVisionAssistant: ChatMessage?
    private var stickyVisionUntil: Date?
    private var autoCompactForConversation: String?

    private var api: CompanionAPI?
    private var media: MediaURLBuilder?
    private var syncCursor: String?
    private var syncTask: Task<Void, Never>?
    private var typingTask: Task<Void, Never>?
    private var modeTask: Task<Void, Never>?
    private var messageReloadTask: Task<Void, Never>?
    private var pendingReloadConversationId: String?
    private var deletedIds: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "nocoai.deletedChats") ?? [])
    private var applyingRemoteMode = false

    private var syncIntervalNs: UInt64 {
        peerTyping ? 450_000_000 : 900_000_000
    }

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
        messageReloadTask?.cancel()
        messageReloadTask = nil
    }

    func loadConversations() async {
        guard let api else { return }
        do {
            let remote = try await api.fetchConversations()
            conversations = remote.filter { !deletedIds.contains($0.id) }
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
                messages = mergePreservingStickyVision(server: serverMessages)
            }
            evaluateChatLimit()
        } catch {
            // Keep existing messages on transient errors — never wipe the thread
            lastError = (error as? LocalizedError)?.errorDescription
        }
    }

    func send(_ text: String) async {
        sendTask?.cancel()
        let task = Task { @MainActor in
            _ = await sendAndReturnReply(text, modeOverride: nil)
        }
        sendTask = task
        await task.value
        if sendTask == task { sendTask = nil }
    }

    /// Sends a chat message and returns the final assistant text (for voice TTS).
    @discardableResult
    func sendAndReturnReply(_ text: String, modeOverride: AIMode? = nil, speak: Bool = false) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let api else { return nil }

        // Speak must never get stuck behind a previous send
        if isSending {
            if speak {
                for _ in 0..<12 {
                    if !isSending { break }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                if isSending { isSending = false }
            } else {
                return nil
            }
        }

        HapticService.prepare()
        HapticService.send()

        isSending = true
        lastError = nil
        let sendMode = speak ? .flash : (modeOverride ?? mode)

        let userMessage = ChatMessage(role: .user, text: trimmed)
        messages.append(userMessage)
        let assistant = ChatMessage(role: .assistant, text: "", isStreaming: true)
        messages.append(assistant)
        let assistantID = assistant.id

        let isStartingNewChat = activeConversationId == nil
        var conversationId = activeConversationId
        var reply: String?

        do {
            for try await chunk in api.streamChatV2(
                message: trimmed,
                conversationId: conversationId,
                mode: sendMode,
                speak: speak
            ) {
                try Task.checkCancellation()
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
                var final = messages[idx].text.trimmingCharacters(in: .whitespacesAndNewlines)
                if speak {
                    final = VoiceService.stripSpeakEcho(final)
                    messages[idx].text = final
                }
                reply = final.isEmpty ? nil : final
            }

            // Speak: return ASAP — resolve/sync in background so TTS starts sooner
            if speak {
                let finalReply = reply
                let cid = conversationId
                let starting = isStartingNewChat
                Task { @MainActor in
                    await resolveConversationId(cid, preferLatest: starting)
                    evaluateChatLimit()
                }
                HapticService.success()
                isSending = false
                return finalReply
            }
            await resolveConversationId(conversationId, preferLatest: isStartingNewChat)
            await syncFromServer()
            evaluateChatLimit()
            HapticService.success()
        } catch is CancellationError {
            if let idx = messages.firstIndex(where: { $0.id == assistantID }) {
                messages[idx].isStreaming = false
                if messages[idx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    messages[idx].text = "(abgebrochen)"
                }
            }
            reply = nil
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

    func cancelSend() {
        sendTask?.cancel()
        sendTask = nil
        Task { try? await api?.interruptChat(conversationId: activeConversationId) }
        if let idx = messages.lastIndex(where: { $0.isStreaming }) {
            messages[idx].isStreaming = false
            if messages[idx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages[idx].text = "(abgebrochen)"
            } else if !messages[idx].text.contains("abgebrochen") {
                messages[idx].text += "\n\n(abgebrochen)"
            }
        }
        isSending = false
        HapticService.soft()
    }

    func sendImage(_ data: Data, caption: String?) async {
        guard let api else { return }

        HapticService.prepare()
        HapticService.rigid()

        let isStartingNewChat = activeConversationId == nil
        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let intent = ImageAttachIntent.resolve(caption: trimmed.isEmpty ? nil : trimmed)

        // Normalize HEIC/PNG → JPEG so vision / SD accept the bytes
        let jpeg = Self.jpegData(from: data)

        if intent == .edit, !trimmed.isEmpty {
            await sendImageEdit(jpeg: jpeg, instruction: trimmed, isStartingNewChat: isStartingNewChat)
            return
        }

        let userText = trimmed.isEmpty ? "Was siehst du auf dem Bild?" : trimmed
        await sendImageVision(jpeg: jpeg, userText: userText, isStartingNewChat: isStartingNewChat)
    }

    private func sendImageVision(jpeg: Data, userText: String, isStartingNewChat: Bool) async {
        guard let api else { return }

        let userMessage = ChatMessage(role: .user, text: userText, localImageData: jpeg)
        messages.append(userMessage)

        isSending = true
        lastError = nil
        defer { isSending = false }

        do {
            let result = try await api.uploadVisionImage(
                imageData: jpeg,
                filename: "upload.jpg",
                message: userText,
                conversationId: activeConversationId
            )

            if let cid = result.conversationId, !cid.isEmpty {
                activeConversationId = cid
                persistActiveConversation()
            }

            var keptAssistant: ChatMessage?
            if let assistant = result.asAssistantMessage() {
                let mapped = mapMessage(assistant)
                messages.append(mapped)
                keptAssistant = mapped
                HapticService.messageReceived()
            } else if let text = result.replyText, !text.isEmpty {
                let mapped = ChatMessage(role: .assistant, text: text)
                messages.append(mapped)
                keptAssistant = mapped
                HapticService.messageReceived()
            }

            if let kept = keptAssistant {
                // Guard against moondream-style "NO" if PC isn't updated yet
                if Self.isUselessVisionReply(kept.text) {
                    if let idx = messages.firstIndex(where: { $0.id == kept.id }) {
                        messages[idx].text = "Bildanalyse unklar — bitte Companion (NOCO AI X) neu starten und nochmal senden."
                    }
                } else {
                    stickyVisionAssistant = kept
                    stickyVisionUntil = Date().addingTimeInterval(90)
                }
            }

            await resolveConversationId(activeConversationId, preferLatest: isStartingNewChat)
            await softSyncPreservingVision(localAssistant: keptAssistant)
            evaluateChatLimit()
            HapticService.success()
        } catch {
            messages.append(ChatMessage(role: .assistant, text: "Bild-Upload fehlgeschlagen: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"))
            lastError = (error as? LocalizedError)?.errorDescription
            HapticService.error()
        }
    }

    private func sendImageEdit(jpeg: Data, instruction: String, isStartingNewChat: Bool) async {
        guard let api else { return }

        let userMessage = ChatMessage(role: .user, text: instruction, localImageData: jpeg)
        messages.append(userMessage)

        let placeholderId = UUID()
        messages.append(ChatMessage(
            id: placeholderId,
            role: .assistant,
            text: "Bearbeite Bild…",
            isStreaming: true
        ))

        isSending = true
        lastError = nil
        defer { isSending = false }

        do {
            let prompt = ImageAttachIntent.editPrompt(from: instruction)
            let denoise = ImageAttachIntent.denoising(for: instruction)
            let result = try await api.editImage(
                prompt: prompt,
                imageJPEG: jpeg,
                conversationId: activeConversationId,
                denoisingStrength: denoise
            )

            if let cid = result.conversationId, !cid.isEmpty {
                activeConversationId = cid
                persistActiveConversation()
            }

            var localData: Data?
            if let b64 = result.imageBase64 {
                let cleaned = b64
                    .replacingOccurrences(of: "\n", with: "")
                    .replacingOccurrences(of: "data:image/png;base64,", with: "")
                    .replacingOccurrences(of: "data:image/jpeg;base64,", with: "")
                localData = Data(base64Encoded: cleaned)
            }

            let url = media?.url(for: result.resolvedPath)
            let replyText = result.content?.isEmpty == false
                ? result.content!
                : "Fertig — \(instruction)"

            if let idx = messages.firstIndex(where: { $0.id == placeholderId }) {
                messages[idx] = ChatMessage(
                    id: placeholderId,
                    role: .assistant,
                    text: replyText,
                    isStreaming: false,
                    imageURL: url,
                    localImageData: localData
                )
            } else {
                messages.append(ChatMessage(
                    role: .assistant,
                    text: replyText,
                    imageURL: url,
                    localImageData: localData
                ))
            }

            if let kept = messages.first(where: { $0.id == placeholderId }) {
                stickyVisionAssistant = kept
                stickyVisionUntil = Date().addingTimeInterval(90)
            }

            await resolveConversationId(activeConversationId, preferLatest: isStartingNewChat)
            await softSyncPreservingVision(localAssistant: messages.first(where: { $0.id == placeholderId }))
            evaluateChatLimit()
            HapticService.success()
            HapticService.messageReceived()
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == placeholderId }) {
                messages[idx] = ChatMessage(
                    id: placeholderId,
                    role: .assistant,
                    text: "Bildbearbeitung fehlgeschlagen: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)",
                    isStreaming: false
                )
            }
            lastError = (error as? LocalizedError)?.errorDescription
            HapticService.error()
        }
    }

    func deleteConversation(_ id: String) async {
        guard let api else { return }
        deletedIds.insert(id)
        persistDeletedIds()
        conversations.removeAll { $0.id == id }
        if activeConversationId == id {
            activeConversationId = nil
            messages = []
            UserDefaults.standard.removeObject(forKey: "nocoai.activeConversation")
        }
        do {
            try await api.deleteConversation(id: id)
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription
        }
        await loadConversations()
        HapticService.medium()
    }

    func setMode(_ newMode: AIMode) {
        guard mode != newMode else { return }
        mode = newMode
        guard !applyingRemoteMode else { return }
        modeTask?.cancel()
        modeTask = Task { [weak self] in
            guard let self, let api = self.api else { return }
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            try? await api.postMode(newMode)
        }
    }

    func publishTyping(_ text: String) {
        guard let api, let cid = activeConversationId else { return }
        typingTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        typingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            do {
                if trimmed.isEmpty {
                    try await api.postTyping(conversationId: cid, typing: false, draftPreview: nil, deviceId: nil)
                } else {
                    try await api.postTyping(
                        conversationId: cid,
                        typing: true,
                        draftPreview: String(trimmed.prefix(80)),
                        deviceId: nil
                    )
                }
            } catch { /* ignore typing errors */ }
        }
    }

    func clearTyping() {
        guard let api, let cid = activeConversationId else { return }
        typingTask?.cancel()
        Task {
            try? await api.postTyping(conversationId: cid, typing: false, draftPreview: nil, deviceId: nil)
        }
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
            applyTypingPresence(res.typing)
            guard !res.events.isEmpty else { return }

            let meaningfulSync = res.events.contains {
                $0.type != "mode.updated" && $0.type != "typing.updated"
            }
            if meaningfulSync {
                isSyncActive = true
                lastSyncAt = .now
            } else {
                lastSyncAt = .now
            }

            var needsConversationList = false
            var messageReloadIds = Set<String>()

            for event in res.events {
                switch event.type {
                case "message.added", "message.created":
                    if let cid = event.conversationId, !deletedIds.contains(cid) {
                        if activeConversationId == nil { activeConversationId = cid }
                        if cid == activeConversationId {
                            messageReloadIds.insert(cid)
                        }
                        needsConversationList = true
                    }
                case "conversation.updated", "conversation.created":
                    let cid = event.conversationId
                    if let cid, deletedIds.contains(cid) {
                        try? await api.deleteConversation(id: cid)
                        continue
                    }
                    needsConversationList = true
                    if let cid, cid == activeConversationId {
                        messageReloadIds.insert(cid)
                    } else if activeConversationId == nil, let cid {
                        activeConversationId = cid
                        messageReloadIds.insert(cid)
                    }
                case "conversation.deleted":
                    if let cid = event.conversationId {
                        applyRemoteDelete(cid)
                    }
                case "typing.updated":
                    guard let cid = event.conversationId, cid == activeConversationId else { continue }
                    guard event.source != "mobile" else { continue }
                    peerTyping = event.typing ?? true
                    peerTypingDraft = event.draftPreview
                case "mode.updated":
                    guard event.source != "mobile" else { continue }
                    let next = AIMode.from(event.mode)
                    applyingRemoteMode = true
                    mode = next
                    applyingRemoteMode = false
                default:
                    break
                }
            }

            if needsConversationList {
                await loadConversations()
            }
            for cid in messageReloadIds {
                scheduleMessageReload(cid)
            }
            if !messageReloadIds.isEmpty {
                HapticService.messageReceived()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.isSyncActive = false
            }
        } catch {
            // Keep last good cursor; next poll retries
        }
    }

    private func scheduleMessageReload(_ cid: String) {
        pendingReloadConversationId = cid
        messageReloadTask?.cancel()
        messageReloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled, let self, let id = self.pendingReloadConversationId else { return }
            self.pendingReloadConversationId = nil
            await self.loadMessages(for: id)
        }
    }

    private func applyTypingPresence(_ list: [TypingPresence]?) {
        guard let list else {
            if peerTyping {
                peerTyping = false
                peerTypingDraft = nil
            }
            return
        }
        let mine = list.first(where: {
            ($0.conversationId == activeConversationId) && ($0.source != "mobile") && ($0.typing == true)
        })
        let next = mine != nil
        let draft = mine?.draftPreview
        if peerTyping != next || peerTypingDraft != draft {
            peerTyping = next
            peerTypingDraft = draft
        }
    }

    private func applyRemoteDelete(_ id: String) {
        deletedIds.insert(id)
        persistDeletedIds()
        conversations.removeAll { $0.id == id }
        if activeConversationId == id {
            activeConversationId = nil
            messages = []
            UserDefaults.standard.removeObject(forKey: "nocoai.activeConversation")
        }
        HapticService.soft()
    }

    private func persistDeletedIds() {
        UserDefaults.standard.set(Array(deletedIds), forKey: "nocoai.deletedChats")
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

    /// Deterministic UUID so reload doesn't reshuffle ForEach identity.
    private func stableUUID(_ serverId: String) -> UUID {
        if let uuid = UUID(uuidString: serverId) { return uuid }
        var bytes = [UInt8](repeating: 0, count: 16)
        let data = Data(serverId.utf8)
        for (i, b) in data.enumerated() {
            bytes[i % 16] ^= b
            bytes[(i * 7) % 16] &+= b &+ UInt8(i & 0xFF)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
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
        var merged = mergePreservingStickyVision(server: server)
        if let streaming = messages.last(where: { $0.isStreaming }) {
            if !merged.contains(where: { $0.serverId == streaming.serverId && streaming.serverId != nil }) {
                merged.append(streaming)
            }
        }
        return merged
    }

    private func mergePreservingStickyVision(server: [ChatMessage]) -> [ChatMessage] {
        var merged = server
        // Keep local photo thumbnails
        for local in messages where local.localImageData != nil {
            if let idx = merged.firstIndex(where: {
                $0.role == .user && $0.localImageData == nil &&
                ($0.text == local.text || $0.id == local.id || $0.serverId == local.serverId)
            }) {
                merged[idx].localImageData = local.localImageData
            } else if !merged.contains(where: { $0.id == local.id }) {
                merged.append(local)
            }
        }

        guard let snap = stickyVisionAssistant else { return merged }
        if let until = stickyVisionUntil, until < Date() {
            stickyVisionAssistant = nil
            stickyVisionUntil = nil
            return merged
        }
        let hasText = merged.contains {
            $0.role == .assistant && !$0.text.isEmpty &&
            ($0.text == snap.text || ($0.serverId != nil && $0.serverId == snap.serverId))
        }
        if hasText {
            stickyVisionAssistant = nil
            stickyVisionUntil = nil
        } else if !merged.contains(where: { $0.id == snap.id }) {
            merged.append(snap)
        }
        return merged
    }

    /// Resize + JPEG so Ollama vision (moondream) does not 500 on huge phone photos.
    private static func jpegData(from data: Data) -> Data {
        guard let img = UIImage(data: data) else { return data }
        let maxSide: CGFloat = 1280
        let w = img.size.width
        let h = img.size.height
        let scale = min(1, maxSide / max(w, h))
        let target = CGSize(width: max(1, floor(w * scale)), height: max(1, floor(h * scale)))
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            img.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.82) ?? data
    }

    /// Moondream often returns closed VQA junk like "NO" / "NO NO NO".
    private static func isUselessVisionReply(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count < 8 { return true }
        let lower = t.lowercased()
        if lower == "no" || lower == "nein" || lower == "yes" || lower == "ja" { return true }
        let compact = lower.replacingOccurrences(of: "[\\s.!?,;]+", with: " ", options: .regularExpression)
        let words = compact.split(separator: " ").map(String.init)
        if words.count <= 6, words.allSatisfy({ ["no", "nein", "yes", "ja"].contains($0) }) {
            return true
        }
        return false
    }

    private func softSyncPreservingVision(localAssistant: ChatMessage?) async {
        let snapshotUser = messages.filter { $0.localImageData != nil }
        let snapshotAssistant = localAssistant ?? stickyVisionAssistant
        if let snap = snapshotAssistant {
            stickyVisionAssistant = snap
            stickyVisionUntil = Date().addingTimeInterval(90)
        }
        await pollSync()
        if let id = activeConversationId {
            try? await Task.sleep(nanoseconds: 450_000_000)
            await loadMessages(for: id)
        }
        await loadConversations()

        // If server reload dropped the vision answer, put it back
        if let snap = snapshotAssistant {
            let hasText = messages.contains {
                $0.role == .assistant && !$0.text.isEmpty &&
                ($0.text == snap.text || $0.serverId == snap.serverId)
            }
            if !hasText {
                messages.append(snap)
                stickyVisionAssistant = snap
                stickyVisionUntil = Date().addingTimeInterval(90)
            }
        }
        // Restore local image thumbnails on matching user bubbles
        for local in snapshotUser {
            if let idx = messages.firstIndex(where: {
                $0.role == .user && $0.localImageData == nil &&
                ($0.text == local.text || $0.id == local.id)
            }) {
                messages[idx].localImageData = local.localImageData
            }
        }
    }

    private func evaluateChatLimit() {
        let reached = messages.count >= softMessageLimit
        chatLimitReached = reached || isCompacting
        guard reached, !isCompacting else { return }
        let key = activeConversationId ?? "local"
        guard autoCompactForConversation != key else { return }
        autoCompactForConversation = key
        Task { await compactChatBecauseLimit() }
    }

    /// Summarize long chat, keep last N messages, drop the rest (new compact thread on PC).
    func compactChatBecauseLimit() async {
        guard let api, let oldId = activeConversationId, !isCompacting else { return }
        isCompacting = true
        chatLimitReached = true
        defer { isCompacting = false }

        let keep = Array(messages.suffix(keepAfterCompact))
        let transcript = messages.suffix(80).map { msg in
            let who = msg.role == .user ? "Nutzer" : "NOCO"
            return "\(who): \(msg.text.prefix(500))"
        }.joined(separator: "\n")

        let prompt = """
        Der Chat ist zu lang. Erstelle eine knappe Zusammenfassung auf Deutsch (8–12 Sätze)
        der wichtigsten Fakten, Entscheidungen und offenen Punkte. Keine Floskeln.
        Danach antwortet das System nur noch mit dieser Zusammenfassung.

        Chat:
        \(transcript.prefix(6000))
        """

        let summary = await sendAndReturnReply(prompt, modeOverride: .flash) ?? ""
        let cleanSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let created = try await api.createConversation(title: "Fortsetzung (Zusammenfassung)")
            if let newId = created.resolvedId {
                activeConversationId = newId
                persistActiveConversation()
                let summaryBubble = ChatMessage(
                    role: .assistant,
                    text: cleanSummary.isEmpty
                        ? "Chat verdichtet — wir machen hier weiter."
                        : "Zusammenfassung bisher:\n\n\(cleanSummary)"
                )
                messages = [summaryBubble] + keep
                if !cleanSummary.isEmpty {
                    _ = await sendAndReturnReply(
                        "[Kontext aus vorherigem Chat]\n\(cleanSummary)\n\nBitte an diesen Kontext anknüpfen. Antworte nur kurz mit OK.",
                        modeOverride: .flash
                    )
                    // Keep UI lean: summary + last messages (drop the seed exchange)
                    messages = [summaryBubble] + keep
                }
                deletedIds.insert(oldId)
                persistDeletedIds()
                try? await api.deleteConversation(id: oldId)
                conversations.removeAll { $0.id == oldId }
                await loadConversations()
                autoCompactForConversation = newId
                chatLimitReached = false
                HapticService.success()
                return
            }
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            messages = Array(keep.suffix(keepAfterCompact))
            if !cleanSummary.isEmpty {
                messages.insert(
                    ChatMessage(role: .assistant, text: "Zusammenfassung:\n\(cleanSummary)"),
                    at: 0
                )
            }
            chatLimitReached = messages.count >= softMessageLimit
            autoCompactForConversation = nil
            HapticService.error()
        }
    }

}
