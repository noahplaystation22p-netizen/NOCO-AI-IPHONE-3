import PhotosUI
import SwiftUI
import UIKit

struct ChatInputBar: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Binding var text: String
    @FocusState.Binding var focused: Bool
    var onSend: () -> Void
    var onVoice: (() -> Void)? = nil
    var onWritingTools: (() -> Void)? = nil

    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var showPlusMenu = false
    @State private var photoItem: PhotosPickerItem?

    private var modeBinding: Binding<AIMode> {
        Binding(
            get: { connection.chat.mode },
            set: {
                if connection.chat.mode != $0 {
                    HapticService.selection()
                }
                connection.chat.setMode($0)
            }
        )
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            plusButton

            TextField("Frag NOCO AI…", text: $text, axis: .vertical)
                .lineLimit(1...8)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { send() }
                .onChange(of: text) { _, newValue in
                    connection.chat.publishTyping(newValue)
                    if newValue.contains(where: { $0 == "\n" || $0 == "\r" }) {
                        text = newValue
                            .replacingOccurrences(of: "\r", with: "")
                            .replacingOccurrences(of: "\n", with: "")
                        send()
                    }
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

            if connection.chat.isSending {
                Button {
                    HapticService.soft()
                    connection.chat.cancelSend()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(NOCOAITheme.danger)
                        .shadow(color: NOCOAITheme.danger.opacity(0.45), radius: 10)
                }
                .accessibilityLabel("Abbrechen")
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 36))
                        .shadow(color: NOCOAITheme.glowPrimary.opacity(0.55), radius: 10)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .foregroundStyle(NOCOAITheme.accent)
                .symbolEffect(.bounce, value: connection.chat.isSending)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .photosPicker(isPresented: $showLibrary, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await sendVision(data)
                }
                photoItem = nil
            }
        }
        .sheet(isPresented: $showPlusMenu) {
            NavigationStack {
                List {
                    Section("Modell") {
                        ForEach(AIMode.allCases) { mode in
                            Button {
                                modeBinding.wrappedValue = mode
                                showPlusMenu = false
                            } label: {
                                HStack {
                                    Label {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(mode.label)
                                            Text(mode.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    } icon: {
                                        Image(systemName: mode.systemImage)
                                    }
                                    Spacer()
                                    if connection.chat.mode == mode {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(NOCOAITheme.accent)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }

                    Section("Bild · Vision") {
                        Button {
                            showPlusMenu = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                showLibrary = true
                            }
                        } label: {
                            Label("Foto auswählen", systemImage: "photo.on.rectangle")
                        }
                        Button {
                            showPlusMenu = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                showCamera = true
                            }
                        } label: {
                            Label("Foto machen", systemImage: "camera.fill")
                        }
                    }

                    if onWritingTools != nil {
                        Section {
                            Button {
                                showPlusMenu = false
                                onWritingTools?()
                            } label: {
                                Label("Schreibwerkzeuge", systemImage: "pencil.and.outline")
                            }
                        }
                    }
                }
                .navigationTitle("Mehr")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fertig") { showPlusMenu = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPickerView { data in
                showCamera = false
                guard let data else { return }
                Task { await sendVision(data) }
            }
            .ignoresSafeArea()
        }
    }

    private var plusButton: some View {
        Image(systemName: "plus.circle.fill")
            .font(.title2)
            .foregroundStyle(NOCOAITheme.accent)
            .shadow(color: NOCOAITheme.glowPrimary.opacity(0.4), radius: 6)
            .frame(width: 36, height: 36)
            .contentShape(Circle())
            .onTapGesture {
                HapticService.light()
                showLibrary = true
            }
            .onLongPressGesture(minimumDuration: 0.4) {
                HapticService.medium()
                showPlusMenu = true
            }
            .accessibilityLabel("Plus — tippen Foto, halten Menü")
            .accessibilityHint("Tippen: Foto. Gedrückt halten: Modelle und Kamera.")
    }

    private func sendVision(_ data: Data) async {
        HapticService.rigid()
        await connection.chat.sendImage(data, caption: text.isEmpty ? nil : text)
        text = ""
        focused = false
    }

    private func send() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        connection.chat.clearTyping()
        focused = false
        onSend()
    }
}

/// Camera capture for Vision uploads.
struct CameraPickerView: UIViewControllerRepresentable {
    var onFinish: (Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (Data?) -> Void
        init(onFinish: @escaping (Data?) -> Void) { self.onFinish = onFinish }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            onFinish(image?.jpegData(compressionQuality: 0.85))
        }
    }
}
