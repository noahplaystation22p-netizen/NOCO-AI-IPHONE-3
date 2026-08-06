import SwiftUI
import UIKit

struct ChatHubView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme
    @State private var input = ""
    @State private var showConversations = false
    @State private var showWritingTools = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let error = connection.chat.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(NOCOAITheme.danger.opacity(0.9))
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        if connection.chat.messages.isEmpty {
                            emptyState
                        } else {
                            LazyVStack(spacing: 16) {
                                ForEach(Array(connection.chat.messages.enumerated()), id: \.element.id) { index, message in
                                    ChatBubble(message: message) { action in
                                        Task {
                                            await connection.chat.send(action.prompt(for: message.text))
                                        }
                                    }
                                    .intelligenceMessageArrive()
                                    .id(message.id)
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.96)),
                                        removal: .opacity
                                    ))
                                    .animation(.spring(response: 0.4, dampingFraction: 0.82).delay(Double(min(index, 6)) * 0.02), value: connection.chat.messages.count)
                                }
                            }
                            .padding(16)
                        }
                    }
                    .onTapGesture { inputFocused = false }
                    .onChange(of: connection.chat.messages.count) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: connection.chat.messages.last?.text) { _, _ in
                        scrollToBottom(proxy)
                    }
                }

                if connection.chat.peerTyping {
                    PeerTypingBanner(draft: connection.chat.peerTypingDraft)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if connection.chat.chatLimitReached || connection.chat.isCompacting {
                    ChatLimitBanner(
                        isCompacting: connection.chat.isCompacting,
                        onCompact: {
                            Task { await connection.chat.compactChatBecauseLimit() }
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                ChatInputBar(
                    text: $input,
                    focused: $inputFocused,
                    onSend: {
                        let text = input
                        input = ""
                        Task { await connection.chat.send(text) }
                    },
                    onVoice: { connection.speak.openUI() },
                    onWritingTools: { showWritingTools = true }
                )
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: connection.chat.peerTyping)
            .nocoBackground()
            .navigationTitle(titleText)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        HapticService.open()
                        showConversations = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        SyncBadge(active: connection.chat.isSyncActive)
                        StatusBadge(
                            online: connection.isOnline,
                            label: connection.isOnline ? "Online" : "Offline"
                        )
                    }
                }
            }
            .sheet(isPresented: $showConversations) {
                ConversationListView()
                    .environmentObject(connection)
            }
            .sheet(isPresented: $showWritingTools) {
                WritingToolsSheet(sourceText: input.isEmpty ? (connection.chat.messages.last(where: { $0.role == .assistant })?.text ?? "") : input) { tool in
                    let source = input.isEmpty
                        ? (connection.chat.messages.last(where: { $0.role == .user || $0.role == .assistant })?.text ?? "")
                        : input
                    guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    input = ""
                    Task { await connection.chat.send(tool.prompt(for: source)) }
                }
            }
            .onAppear { HapticService.prepare() }
            .intelligenceSelectionFeedback(connection.chat.mode)
            .task {
                connection.chat.restoreSession()
                await connection.chat.loadConversations()
                connection.chat.ensureActiveIsNotKeyboard()
                if let id = connection.chat.activeConversationId {
                    await connection.chat.loadMessages(for: id)
                } else if let first = connection.chat.filteredConversations.first {
                    await connection.chat.selectConversation(first.id)
                }
            }
        }
    }

    private var titleText: String {
        connection.chat.conversations.first(where: { $0.id == connection.chat.activeConversationId })?.title ?? "Chat"
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                IntelligenceOrbitRings(size: 130)
                    .opacity(0.45)
                Circle()
                    .fill(NOCOAITheme.glowPrimary.opacity(0.16))
                    .frame(width: 88, height: 88)
                    .blur(radius: 16)
                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(NOCOAITheme.accent)
                    .shadow(color: NOCOAITheme.glowPrimary.opacity(0.75), radius: 16)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            }
            Text("Frag irgendetwas")
                .font(.title3.weight(.semibold))
            Text("Dein PC rechnet — Antworten streamen\nweich flüssig und klar.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(NOCOAITheme.secondaryText(for: scheme))
                .padding(.horizontal, 28)

            IntelligenceWaveRibbon()
                .frame(height: 32)
                .padding(.horizontal, 40)

            IntelligenceShimmerLine()
                .padding(.horizontal, 60)

            FloatingIntelligenceDots(count: 3)
                .frame(height: 56)
                .padding(.horizontal, 36)

            IntelligenceIdeaChips { idea in
                Task { await connection.chat.send(idea.prompt) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let last = connection.chat.messages.last {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

private struct PeerTypingBanner: View {
    var draft: String?
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [NOCOAITheme.glowPrimary, NOCOAITheme.glowSecondary],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 7, height: 7)
                        .scaleEffect(phase == i ? 1.35 : 0.8)
                        .opacity(phase == i ? 1 : 0.35)
                        .shadow(color: NOCOAITheme.glowPrimary.opacity(phase == i ? 0.7 : 0), radius: 5)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("PC tippt…")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NOCOAITheme.accent)
                if let draft, !draft.isEmpty {
                    Text(draft)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(NOCOAITheme.glowPrimary.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: NOCOAITheme.glowPrimary.opacity(0.2), radius: 10)
        )
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 280_000_000)
                phase = (phase + 1) % 3
            }
        }
    }
}

private struct ChatBubble: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme
    let message: ChatMessage
    var onReplyAction: ((ReplyAction) -> Void)?

    var body: some View {
        HStack(alignment: .bottom) {
            if message.role == .user { Spacer(minLength: 48) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                if let data = message.localImageData, let uiImage = UIImage(data: data) {
                    Button {
                        HapticService.soft()
                        connection.openGalleryImage(url: message.imageURL, serverId: message.serverId)
                    } label: {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: NOCOAITheme.glowPrimary.opacity(0.25), radius: 12)
                    }
                    .buttonStyle(.plain)
                } else if let url = message.imageURL {
                    Button {
                        HapticService.soft()
                        connection.openGalleryImage(url: url, serverId: message.serverId)
                    } label: {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFit().frame(maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 16))
                            case .failure:
                                Image(systemName: "photo").frame(height: 120)
                            default:
                                ProgressView().frame(height: 120)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                if !message.text.isEmpty || message.isStreaming {
                    if message.isStreaming && message.text.isEmpty {
                        IntelligenceThinkingDots()
                    } else {
                        HStack(alignment: .bottom, spacing: 6) {
                            Text(message.text)
                                .font(.body)
                                .foregroundStyle(message.role == .user ? .white : NOCOAITheme.primaryText(for: scheme))
                                .textSelection(.enabled)
                            if message.isStreaming {
                                StreamingGlowCursor()
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(GlowBubbleBackground(isUser: message.role == .user))
                        .animation(.easeOut(duration: 0.12), value: message.text)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = message.text
                                HapticService.success()
                            } label: {
                                Label("Kopieren", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }

                if !message.isStreaming, !message.text.isEmpty {
                    HStack(spacing: 8) {
                        Button {
                            UIPasteboard.general.string = message.text
                            HapticService.success()
                        } label: {
                            Label("Kopieren", systemImage: "doc.on.doc")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)

                        if message.role == .assistant, let onReplyAction {
                            ReplyActionBar(replyText: message.text, onAction: onReplyAction)
                        }
                    }
                }
            }
            if message.role == .assistant { Spacer(minLength: 48) }
        }
    }
}

struct ConversationListView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        HapticService.medium()
                        Task {
                            _ = await connection.chat.newConversation()
                            dismiss()
                        }
                    } label: {
                        Label("Neuer Chat", systemImage: "plus.bubble.fill")
                    }
                }
                Section("Unterhaltungen") {
                    ForEach(connection.chat.filteredConversations) { convo in
                        Button {
                            Task {
                                await connection.chat.selectConversation(convo.id)
                                dismiss()
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(convo.title).font(.headline)
                                if let updated = convo.updatedAt {
                                    Text(updated).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await connection.chat.deleteConversation(convo.id) }
                            } label: { Label("Löschen", systemImage: "trash") }
                        }
                    }
                }
                if !connection.chat.keyboardConversations.isEmpty {
                    Section {
                        ForEach(connection.chat.keyboardConversations) { convo in
                            Button {
                                Task {
                                    await connection.chat.selectConversation(convo.id)
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "keyboard")
                                        .foregroundStyle(NOCOAITheme.accent)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(convo.title.isEmpty ? "Tastatur" : convo.title)
                                            .font(.headline)
                                        Text("Verbessern · Kürzer · Antwort …")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task { await connection.chat.deleteConversation(convo.id) }
                                } label: { Label("Löschen", systemImage: "trash") }
                            }
                        }
                    } header: {
                        Label("Tastatur", systemImage: "keyboard")
                    } footer: {
                        Text("Keyboard-Aktionen landen hier — nicht in normalen Chats.")
                    }
                }
            }
            .searchable(text: Binding(
                get: { connection.chat.searchText },
                set: { connection.chat.searchText = $0 }
            ), prompt: "Chats suchen")
            .navigationTitle("Unterhaltungen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}


private struct ChatLimitBanner: View {
    var isCompacting: Bool
    var onCompact: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.badge.minus")
                .foregroundStyle(NOCOAITheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(isCompacting ? "Chat wird verdichtet…" : "Chat-Limit erreicht")
                    .font(.subheadline.weight(.semibold))
                Text(isCompacting
                     ? "Zusammenfassung läuft automatisch…"
                     : "Über ~35 Nachrichten — verdichtet automatisch oder tippe hier.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !isCompacting {
                Button("Verdichten", action: onCompact)
                    .font(.caption.weight(.bold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                ProgressView()
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(NOCOAITheme.glowPrimary.opacity(0.35), lineWidth: 1)
        )
    }
}
