import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Minimal chat composer — all extras live in the + panel.
struct ChatInputBar: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme
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
    /// Unified press tracking — avoids LongPress stealing taps.
    @State private var plusTouchStart: Date?
    @State private var plusTouchOrigin: CGPoint = .zero
    @State private var plusLongArmed = false

    private let plusLongThreshold: TimeInterval = 0.38
    private let plusTapSlop: CGFloat = 14

    var body: some View {
        VStack(spacing: 8) {
            if let once = connection.chat.liveKnowledgeOnce {
                HStack(spacing: 8) {
                    Image(systemName: once == .web ? "globe" : "lock.laptopcomputer")
                        .font(.caption.weight(.semibold))
                    Text(once == .web
                         ? "🌐 Nächste Antwort: Internet"
                         : "Nur lokal für nächste Antwort")
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 0)
                    Button("Abbrechen") {
                        connection.chat.clearLiveKnowledgeArm()
                        HapticService.soft()
                    }
                    .font(.caption.weight(.semibold))
                }
                .foregroundStyle(once == .web ? Color(red: 0.25, green: 0.55, blue: 0.95) : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .padding(.horizontal, 4)
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
                .accessibilityLabel("Voice AI")

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
        .padding(.top, 8)
        .padding(.bottom, 8)
        // Opaque bar so material/aura never bleeds over the chat (“Frag NOCO”).
        .background {
            Rectangle()
                .fill(Color(.systemBackground).opacity(scheme == .dark ? 0.92 : 0.94))
                .overlay(Rectangle().fill(.ultraThinMaterial.opacity(0.55)))
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [
                            Color(.systemBackground).opacity(0.98),
                            Color(.systemBackground).opacity(0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 10)
                }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.08), radius: 8, y: -2)
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
        .animation(.spring(response: 0.35, dampingFraction: 0.84), value: showPlus)
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
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
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
            .gesture(plusPressGesture)
            .accessibilityLabel("Werkzeuge")
            .accessibilityHint("Tippen für detailliertes Menü, gedrückt halten für Schnellauswahl")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                HapticService.open()
                showPlus = true
            }
    }

    /// One DragGesture: short release = detailed sheet; hold = quick picker + slide to select.
    private var plusPressGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if plusTouchStart == nil {
                    plusTouchStart = Date()
                    plusTouchOrigin = value.startLocation
                    plusLongArmed = false
                }
                let held = Date().timeIntervalSince(plusTouchStart ?? .now)
                let moved = hypot(
                    value.location.x - plusTouchOrigin.x,
                    value.location.y - plusTouchOrigin.y
                )
                if !plusLongArmed, held >= plusLongThreshold, moved < 40 {
                    plusLongArmed = true
                    showQuickPicker = true
                    focused = false
                    PlusQuickPickerWindow.show(anchor: plusAnchor, highlight: .camera)
                    HapticService.rigid()
                }
                if plusLongArmed {
                    PlusQuickPickerWindow.update(finger: value.location, highlight: nil)
                }
            }
            .onEnded { value in
                let start = plusTouchStart ?? .now
                let held = Date().timeIntervalSince(start)
                let moved = hypot(
                    value.location.x - plusTouchOrigin.x,
                    value.location.y - plusTouchOrigin.y
                )
                let wasLong = plusLongArmed
                plusTouchStart = nil
                plusLongArmed = false

                if wasLong {
                    let selected = PlusQuickPickerWindow.currentHighlight
                    PlusQuickPickerWindow.hide(animated: true)
                    showQuickPicker = false
                    if let selected {
                        HapticService.open()
                        performQuickAction(selected)
                    }
                } else if held < plusLongThreshold, moved < plusTapSlop, !showQuickPicker {
                    // Clean tap → detailed Werkzeuge panel only
                    HapticService.open()
                    showPlus = true
                } else {
                    PlusQuickPickerWindow.hide(animated: true)
                    showQuickPicker = false
                }
            }
    }

    private func performQuickAction(_ action: PlusQuickAction) {
        switch action {
        case .camera:
            showCamera = true
        case .vision:
            onVoice?()
        case .liveWeb:
            connection.chat.armLiveKnowledge(.web)
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
                                colors: NOCORainbow.flow,
                                center: .center
                            )
                            : AngularGradient(
                                colors: NOCORainbow.flow.map { $0.opacity(0.22) },
                                center: .center
                            ),
                        lineWidth: focused || connection.chat.isSending ? 1.4 : 1
                    )
            )
            .shadow(color: NOCORainbow.blue.opacity(focused ? 0.28 : 0.08), radius: focused ? 14 : 6, y: 2)
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
