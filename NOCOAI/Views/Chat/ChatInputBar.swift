import PhotosUI
import SwiftUI

struct ChatInputBar: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Binding var text: String
    @FocusState.Binding var focused: Bool
    var onSend: () -> Void
    var onVoice: (() -> Void)? = nil
    var onWritingTools: (() -> Void)? = nil

    @State private var showAttachments = false
    @State private var photoItem: PhotosPickerItem?

    private var modeBinding: Binding<AIMode> {
        Binding(
            get: { connection.chat.mode },
            set: {
                if connection.chat.mode != $0 {
                    HapticService.selection()
                }
                connection.chat.mode = $0
            }
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            ModePicker(mode: modeBinding)
                .padding(.horizontal, 4)

            HStack(alignment: .bottom, spacing: 10) {
                Menu {
                    Button("Visuelle Intelligenz", systemImage: "eye") {
                        HapticService.light()
                        showAttachments = true
                    }
                    Button("Schreibwerkzeuge", systemImage: "pencil.and.outline") {
                        HapticService.light()
                        onWritingTools?()
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(NOCOAITheme.accent)
                        .shadow(color: NOCOAITheme.glowPrimary.opacity(0.4), radius: 6)
                }

                TextField("Frag NOCO AI…", text: $text, axis: .vertical)
                    .lineLimit(1...8)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { send() }
                    .onChange(of: text) { _, newValue in
                        connection.chat.publishTyping(newValue)
                    }
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { connection.chat.clearTyping() }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(
                                        focused
                                            ? NOCOAITheme.glowPrimary.opacity(0.65)
                                            : Color.primary.opacity(0.08),
                                        lineWidth: focused ? 1.2 : 1
                                    )
                            )
                            .shadow(color: focused ? NOCOAITheme.glowPrimary.opacity(0.35) : .clear, radius: focused ? 14 : 0)
                    )

                Button {
                    HapticService.medium()
                    focused = false
                    onVoice?()
                } label: {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.35, green: 0.8, blue: 1),
                                    Color(red: 0.65, green: 0.4, blue: 1),
                                    Color(red: 1.0, green: 0.4, blue: 0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color(red: 0.55, green: 0.4, blue: 1).opacity(0.55), radius: 10)
                }
                .disabled(!connection.isOnline || connection.chat.isSending)
                .opacity(connection.isOnline ? 1 : 0.4)
                .accessibilityLabel("Speak")

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 36))
                        .shadow(color: NOCOAITheme.glowPrimary.opacity(0.55), radius: 10)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || connection.chat.isSending)
                .foregroundStyle(NOCOAITheme.accent)
                .symbolEffect(.bounce, value: connection.chat.isSending)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .photosPicker(isPresented: $showAttachments, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    HapticService.rigid()
                    await connection.chat.sendImage(data, caption: text.isEmpty ? nil : text)
                    text = ""
                    focused = false
                }
                photoItem = nil
            }
        }
    }

    private func send() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        connection.chat.clearTyping()
        focused = false
        onSend()
    }
}
