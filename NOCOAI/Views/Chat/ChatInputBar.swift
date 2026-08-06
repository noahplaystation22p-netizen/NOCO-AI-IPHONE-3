import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CoreTransferable

struct ChatInputBar: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Binding var text: String
    @FocusState.Binding var focused: Bool
    var onSend: () -> Void
    var onVoice: (() -> Void)? = nil
    var onWritingTools: (() -> Void)? = nil

    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var scrubMenuVisible = false
    @State private var scrubSelection = 0

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
        ZStack(alignment: .bottomLeading) {
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
                    if isFocused {
                        HapticService.focus()
                    } else {
                        connection.chat.clearTyping()
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(
                                    connection.chat.isSending
                                        ? AngularGradient(
                                            colors: [
                                                NOCOAITheme.glowPrimary,
                                                NOCOAITheme.glowSecondary,
                                                NOCOAITheme.glowAccent,
                                                NOCOAITheme.glowPrimary
                                            ],
                                            center: .center
                                        )
                                        : AngularGradient(
                                            colors: [
                                                focused
                                                    ? NOCOAITheme.glowPrimary.opacity(0.65)
                                                    : Color.primary.opacity(0.08),
                                                focused
                                                    ? NOCOAITheme.glowSecondary.opacity(0.4)
                                                    : Color.primary.opacity(0.08)
                                            ],
                                            center: .center
                                        ),
                                    lineWidth: focused || connection.chat.isSending ? 1.4 : 1
                                )
                        )
                        .shadow(
                            color: (focused || connection.chat.isSending)
                                ? NOCOAITheme.glowPrimary.opacity(0.35)
                                : .clear,
                            radius: focused || connection.chat.isSending ? 14 : 0
                        )
                )
                .animation(.easeInOut(duration: 0.35), value: connection.chat.isSending)

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
                                Color(red: 0.58, green: 0.48, blue: 0.98),
                                Color(red: 0.95, green: 0.55, blue: 0.78)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color(red: 0.55, green: 0.45, blue: 1).opacity(0.5), radius: 10)
                    .symbolEffect(.bounce, value: connection.speak.isRunning)
                }
                .buttonStyle(IntelligencePressStyle(haptic: { HapticService.soft() }))
                .disabled(!connection.isOnline || connection.chat.isSending)
                .opacity(connection.isOnline ? 1 : 0.4)
                .accessibilityLabel("Speak")

                if connection.chat.isSending {
                Button {
                    HapticService.warning()
                    connection.chat.cancelSend()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(NOCOAITheme.danger)
                        .shadow(color: NOCOAITheme.danger.opacity(0.45), radius: 10)
                }
                .buttonStyle(IntelligencePressStyle(haptic: { HapticService.rigid() }))
                .accessibilityLabel("Abbrechen")
                } else {
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 36))
                        .shadow(color: NOCOAITheme.glowPrimary.opacity(0.55), radius: 10)
                }
                .buttonStyle(IntelligencePressStyle(haptic: { HapticService.soft() }))
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .foregroundStyle(NOCOAITheme.accent)
                .symbolEffect(.bounce, value: connection.chat.isSending)
                }
            }

            if scrubMenuVisible {
                scrubMenu
                    .offset(x: 0, y: -52)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .photosPicker(isPresented: $showLibrary, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task {
                if let data = await ChatPhotoLoader.loadJPEG(from: item) {
                    await sendVision(data)
                } else {
                    HapticService.error()
                    connection.chat.lastError = "Foto konnte nicht geladen werden — erneut versuchen"
                }
                photoItem = nil
            }
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
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !scrubMenuVisible {
                            scrubSelection = 0
                            withAnimation(.snappy) { scrubMenuVisible = true }
                            HapticService.longPress()
                        }
                        let next = min(max(Int((-value.translation.height + 22) / 48), 0), scrubItems.count - 1)
                        if next != scrubSelection {
                            scrubSelection = next
                            HapticService.whisper()
                        }
                    }
                    .onEnded { _ in
                        let selection = scrubSelection
                        withAnimation(.snappy) { scrubMenuVisible = false }
                        activateScrubItem(at: selection)
                    }
            )
            .accessibilityLabel("Plus — Foto, Kamera, Modell und Schreibwerkzeuge")
    }

    private var scrubItems: [ScrubItem] {
        var items: [ScrubItem] = [
            .init(title: "Foto", icon: "photo.on.rectangle", action: .library),
            .init(title: "Kamera", icon: "camera.fill", action: .camera)
        ]
        items += AIMode.allCases.map { .init(title: $0.label, icon: $0.systemImage, action: .mode($0)) }
        if onWritingTools != nil {
            items.append(.init(title: "Schreibwerkzeuge", icon: "pencil.and.outline", action: .writingTools))
        }
        return items
    }

    private var scrubMenu: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(scrubItems.indices.reversed(), id: \.self) { index in
                let item = scrubItems[index]
                Label(item.title, systemImage: item.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(index == scrubSelection ? .white : .primary)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(
                        Capsule().fill(index == scrubSelection ? NOCOAITheme.accent : Color.primary.opacity(0.08))
                    )
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
    }

    private func activateScrubItem(at index: Int) {
        guard scrubItems.indices.contains(index) else { return }
        HapticService.success()
        switch scrubItems[index].action {
        case .library:
            showLibrary = true
        case .camera:
            showCamera = true
        case .mode(let mode):
            modeBinding.wrappedValue = mode
        case .writingTools:
            onWritingTools?()
        }
    }

    private struct ScrubItem: Identifiable {
        enum Action {
            case library, camera, mode(AIMode), writingTools
        }

        let title: String
        let icon: String
        let action: Action
        var id: String { title }
    }

    private func sendVision(_ data: Data) async {
        HapticService.imageSnap()
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

/// Reliable PhotosPicker → JPEG (plain Data transferable often fails on HEIC library assets).
enum ChatPhotoLoader {
    struct TransferImage: Transferable {
        let data: Data

        static var transferRepresentation: some TransferRepresentation {
            DataRepresentation(importedContentType: .image) { data in
                TransferImage(data: data)
            }
            DataRepresentation(importedContentType: .jpeg) { data in
                TransferImage(data: data)
            }
            DataRepresentation(importedContentType: .png) { data in
                TransferImage(data: data)
            }
            DataRepresentation(importedContentType: .heic) { data in
                TransferImage(data: data)
            }
        }
    }

    static func loadJPEG(from item: PhotosPickerItem) async -> Data? {
        if let transfer = try? await item.loadTransferable(type: TransferImage.self),
           let ui = UIImage(data: transfer.data),
           let jpeg = ui.jpegData(compressionQuality: 0.9) {
            return jpeg
        }
        if let data = try? await item.loadTransferable(type: Data.self),
           let ui = UIImage(data: data),
           let jpeg = ui.jpegData(compressionQuality: 0.9) {
            return jpeg
        }
        return nil
    }
}
