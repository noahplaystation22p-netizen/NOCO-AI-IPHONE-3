import PhotosUI
import SwiftUI

struct ChatInputBar: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Binding var text: String
    @FocusState.Binding var focused: Bool
    var onSend: () -> Void

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
                    Button("Bild auswählen", systemImage: "photo") {
                        HapticService.light()
                        showAttachments = true
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(NOCOAITheme.accent)
                }

                TextField("Frag NOCO AI…", text: $text, axis: .vertical)
                    .lineLimit(1...8)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { send() }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color.primary.opacity(0.06)))

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || connection.chat.isSending)
                .foregroundStyle(NOCOAITheme.accent)
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
        focused = false
        onSend()
    }
}