import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Minimal chat composer — all extras live in the + panel.
struct ChatInputBar: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Binding var text: String
    @FocusState.Binding var focused: Bool
    var onSend: () -> Void
    var onVoice: (() -> Void)? = nil
    var onWritingTools: (() -> Void)? = nil

    @State private var showPlus = false
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showDocumentPicker = false
    @State private var showFilePicker = false
    @State private var showQuickPicker = false
    @State private var plusAnchor: CGPoint = .zero
    @State private var suppressPlusTap = false

    var body: some View {
        VStack(spacing: 8) {
            if connection.chat.workPhase != .idle {
                ModeStatusTheater(phase: connection.chat.workPhase, mode: connection.chat.mode)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if let intake = connection.chat.pendingAgentIntake {
                AgentIntakeHint(questions: intake.questions)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(alignment: .bottom, spacing: 10) {
                plusButton

                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...8)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { send() }
                    .onChange(of: text) { _, newValue in
                        connection.chat.publishTyping(newValue)
                        connection.chat.noteDraftChanged(newValue)
                        if newValue.contains(where: { $0 == "\n" || $0 == "\r" }) {
                            text = newValue
                                .replacingOccurrences(of: "\r", with: "")
                                .replacingOccurrences(of: "\n", with: "")
                            send()
                        }
                    }
                    .onChange(of: focused) { _, isFocused in
                        if isFocused { HapticService.focus() }
                        else { connection.chat.clearTyping() }
                    }
                    .padding(14)
                    .background(composerBackground)

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
                        .shadow(color: Color(red: 0.55, green: 0.45, blue: 1).opacity(0.45), radius: 10)
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
                    }
                    .accessibilityLabel("Abbrechen")
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(NOCOAITheme.accent)
                            .shadow(color: NOCOAITheme.glowPrimary.opacity(0.5), radius: 10)
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(IntelligencePressStyle(haptic: { HapticService.soft() }))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .animation(.spring(response: 0.35, dampingFraction: 0.84), value: connection.chat.workPhase)
        .animation(.spring(response: 0.35, dampingFraction: 0.84), value: connection.chat.pendingAgentIntake != nil)
        .sheet(isPresented: $showPlus) {
            PlusToolsPanel(
                onCamera: { showCamera = true },
                onLibrary: { showLibrary = true },
                onDocument: { showDocumentPicker = true },
                onFile: { showFilePicker = true },
                onWritingTools: { onWritingTools?() }
            )
            .environmentObject(connection)
        }
        .photosPicker(isPresented: $showLibrary, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = await ChatPhotoLoader.loadJPEG(from: item) {
                    await sendVision(data)
                } else {
                    HapticService.error()
                    connection.chat.lastError = "Foto konnte nicht geladen werden"
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
        .fileImporter(
            isPresented: $showDocumentPicker,
            allowedContentTypes: [.pdf, .plainText, .utf8PlainText],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await importDocument(url, preferWriting: true) }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item, .data, .image, .pdf, .plainText],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await importDocument(url, preferWriting: false) }
        }
        .onDisappear {
            PlusQuickPickerWindow.hide()
        }
    }

    private var plusButton: some View {
        Image(systemName: "plus.circle.fill")
            .font(.system(size: 32))
            .foregroundStyle(NOCOAITheme.accent)
            .shadow(color: NOCOAITheme.glowPrimary.opacity(0.35), radius: 6)
            .symbolEffect(.bounce, value: showPlus || showQuickPicker)
            .background(
                GeometryReader { g in
                    Color.clear.preference(
                        key: PlusAnchorKey.self,
                        value: CGPoint(
                            x: g.frame(in: .global).midX,
                            y: g.frame(in: .global).midY
                        )
                    )
                }
            )
            .onPreferenceChange(PlusAnchorKey.self) { plusAnchor = $0 }
            .contentShape(Circle().inset(by: -8))
            .gesture(plusGesture)
            .accessibilityLabel("Werkzeuge")
            .accessibilityHint("Tippen für Menü, gedrückt halten für Schnellauswahl")
    }

    private var plusGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.32)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                switch value {
                case .first(true):
                    if !showQuickPicker {
                        suppressPlusTap = true
                        showQuickPicker = true
                        focused = false
                        PlusQuickPickerWindow.show(anchor: plusAnchor, highlight: .camera)
                        HapticService.rigid()
                    }
                case .second(true, let drag):
                    if let drag {
                        PlusQuickPickerWindow.update(finger: drag.location, highlight: nil)
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                let selected = PlusQuickPickerWindow.currentHighlight
                PlusQuickPickerWindow.hide()
                showQuickPicker = false
                if let selected {
                    HapticService.open()
                    performQuickAction(selected)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    suppressPlusTap = false
                }
            }
            .exclusively(before: TapGesture().onEnded {
                guard !suppressPlusTap, !showQuickPicker else { return }
                HapticService.open()
                showPlus = true
            })
    }

    private func performQuickAction(_ action: PlusQuickAction) {
        switch action {
        case .camera:
            showCamera = true
        case .vision:
            onVoice?()
        case .agent:
            connection.chat.setMode(.agent)
        case .createImage:
            connection.handoffToImages(prompt: "")
        case .file:
            showFilePicker = true
        case .writing:
            onWritingTools?()
        }
    }

    private var placeholder: String {
        if connection.chat.pendingAgentIntake != nil {
            return "Antworten auf die Agent-Fragen…"
        }
        switch connection.chat.mode {
        case .agent: return "Ziel für den Agent…"
        case .image: return "Bild erstellen…"
        case .think: return "Tiefe Frage…"
        case .flash: return "Kurze Frage…"
        default: return "Frag NOCO…"
        }
    }

    private var composerBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        focused || connection.chat.isSending
                            ? AngularGradient(
                                colors: [NOCOAITheme.glowPrimary, NOCOAITheme.glowSecondary, NOCOAITheme.glowAccent, NOCOAITheme.glowPrimary],
                                center: .center
                            )
                            : AngularGradient(
                                colors: [Color.primary.opacity(0.08), Color.primary.opacity(0.08)],
                                center: .center
                            ),
                        lineWidth: focused || connection.chat.isSending ? 1.3 : 1
                    )
            )
    }

    private func send() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        connection.chat.clearTyping()
        onSend()
    }

    private func sendVision(_ data: Data) async {
        HapticService.imageSnap()
        await connection.chat.sendImage(data, caption: text.isEmpty ? nil : text)
        text = ""
        focused = false
    }

    private func importDocument(_ url: URL, preferWriting: Bool) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            if UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true {
                await sendVision(data)
                return
            }
            let textBody = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
            let snippet = textBody.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !snippet.isEmpty else {
                connection.chat.lastError = "Datei konnte nicht gelesen werden"
                return
            }
            let name = url.lastPathComponent
            text = "Dokument „\(name)“:\n\n\(snippet.prefix(6000))\n\nBitte analysieren."
            if preferWriting { connection.chat.setMode(.writing) }
            HapticService.success()
        } catch {
            connection.chat.lastError = "Datei nicht lesbar"
            HapticService.error()
        }
    }
}

private struct PlusAnchorKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}

private struct AgentIntakeHint: View {
    let questions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Agent wartet auf deine Antworten")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(red: 0.35, green: 0.78, blue: 0.72))
            ForEach(questions, id: \.self) { q in
                Text("• \(q)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
