import SwiftUI
import UIKit

struct ChatHubView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme
    @State private var input = ""
    @State private var showConversations = false
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
                            LazyVStack(spacing: 14) {
                                ForEach(connection.chat.messages) { message in
                                    ChatBubble(message: message)
                                        .id(message.id)
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

                ChatInputBar(text: $input, focused: $inputFocused) {
                    let text = input
                    input = ""
                    Task { await connection.chat.send(text) }
                }
            }
            .nocoBackground()
            .navigationTitle(titleText)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        HapticService.light()
                        showConversations = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        SyncBadge(active: connection.chat.isSyncActive)
                        StatusBadge(online: connection.isOnline, label: connection.isOnline ? "Live" : "Offline")
                    }
                }
            }
            .sheet(isPresented: $showConversations) {
                ConversationListView()
                    .environmentObject(connection)
            }
            .onAppear { HapticService.prepare() }
            .task {
                connection.chat.restoreSession()
                await connection.chat.loadConversations()
                if let id = connection.chat.activeConversationId {
                    await connection.chat.loadMessages(for: id)
                } else if let first = connection.chat.conversations.first {
                    await connection.chat.selectConversation(first.id)
                }
            }
        }
    }

    private var titleText: String {
        connection.chat.conversations.first(where: { $0.id == connection.chat.activeConversationId })?.title ?? "Chat"
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 48))
                .foregroundStyle(NOCOAITheme.accent.opacity(0.5))
            Text("Schreib eine Nachricht — sie erscheint sofort auf deinem PC.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(NOCOAITheme.secondaryText(for: scheme))
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let last = connection.chat.messages.last {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

private struct ChatBubble: View {
    @Environment(\.colorScheme) private var scheme
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom) {
            if message.role == .user { Spacer(minLength: 48) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                if let data = message.localImageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                } else if let url = message.imageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFit().frame(maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 14))
                        case .failure:
                            Image(systemName: "photo").frame(height: 120)
                        default:
                            ProgressView().frame(height: 120)
                        }
                    }
                }
                if !message.text.isEmpty || message.isStreaming {
                    Text(message.text.isEmpty && message.isStreaming ? "…" : message.text)
                        .font(.body)
                        .foregroundStyle(message.role == .user ? .white : NOCOAITheme.primaryText(for: scheme))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(message.role == .user ? NOCOAITheme.accent : NOCOAITheme.cardFill(for: scheme))
                        )
                        .animation(.easeOut(duration: 0.15), value: message.text)
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
                Section("Chats") {
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
