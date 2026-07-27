import SwiftUI

struct CodeStudioView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme
    @State private var input = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !connection.code.previewCode.isEmpty {
                    ScrollView {
                        Text(connection.code.previewCode)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                    .frame(maxHeight: 220)
                    .background(NOCOAITheme.cardFill(for: scheme))
                }

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(connection.code.messages) { msg in
                            HStack {
                                if msg.role == .user { Spacer(minLength: 40) }
                                Text(msg.text.isEmpty && msg.isStreaming ? "…" : msg.text)
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 16).fill(
                                        msg.role == .user ? NOCOAITheme.accent.opacity(0.9) : NOCOAITheme.cardFill(for: scheme)
                                    ))
                                    .foregroundStyle(msg.role == .user ? .white : NOCOAITheme.primaryText(for: scheme))
                                if msg.role == .assistant { Spacer(minLength: 40) }
                            }
                        }
                    }
                    .padding(16)
                }

                HStack(spacing: 10) {
                    TextField("Code-Anfrage…", text: $input, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($focused)
                        .submitLabel(.send)
                        .onSubmit { send() }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.06)))
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(16)
                .background(.ultraThinMaterial)
            }
            .nocoBackground()
            .navigationTitle(connection.code.activeSession?.title ?? "Code Studio")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(connection.code.sessions) { session in
                            Button(session.title ?? session.id) {
                                connection.code.select(session)
                            }
                        }
                    } label: {
                        Image(systemName: "folder")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Neu") {
                        Task { await connection.code.createSession() }
                    }
                    Button("Workspace") {
                        Task { await connection.code.initWorkspace() }
                    }
                }
            }
            .task { await connection.code.loadSessions() }
        }
    }

    private func send() {
        let text = input
        input = ""
        focused = false
        Task { await connection.code.send(text) }
    }
}
