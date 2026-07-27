import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            if connection.messages.isEmpty {
                                emptyState
                            }
                            ForEach(connection.messages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: connection.messages.count) { _, _ in
                        if let last = connection.messages.last {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: connection.messages.last?.text) { _, _ in
                        if let last = connection.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }

                inputBar
            }
            .nocoBackground()
            .navigationTitle("Chat")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    StatusBadge(online: connection.isOnline, label: connection.isOnline ? "Live" : "Offline")
                }
            }
        }
    }

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(NOCOAITheme.accent)
                Text("Stelle eine Frage an deine lokale KI")
                    .font(.headline)
                Text("Antworten werden live vom PC gestreamt.")
                    .font(.footnote)
                    .foregroundStyle(NOCOAITheme.secondaryText(for: scheme))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Nachricht…", text: $input, axis: .vertical)
                .lineLimit(1...6)
                .focused($inputFocused)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(NOCOAITheme.cardFill(for: scheme))
                )

            Button {
                let text = input
                input = ""
                inputFocused = false
                Task { await connection.sendMessage(text) }
            } label: {
                Image(systemName: connection.isSending ? "ellipsis" : "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .symbolEffect(.pulse, isActive: connection.isSending)
            }
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || connection.isSending || !connection.isOnline)
            .foregroundStyle(NOCOAITheme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}

private struct ChatBubble: View {
    @Environment(\.colorScheme) private var scheme
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                Text(message.text.isEmpty && message.isStreaming ? "…" : message.text)
                    .font(.body)
                    .foregroundStyle(message.role == .user ? Color.white : NOCOAITheme.primaryText(for: scheme))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(message.role == .user ? NOCOAITheme.accent : NOCOAITheme.cardFill(for: scheme))
                    )
                if message.isStreaming {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}
