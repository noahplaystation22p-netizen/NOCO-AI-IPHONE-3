import PhotosUI
import SwiftUI
import UIKit

/// Premium floating Live Screen experience — Apple-inspired assist layer.
struct LiveScreenView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var session: LiveScreenSessionController { connection.liveScreen }
    @State private var photoItem: PhotosPickerItem?
    @State private var draft = ""
    @State private var showConsent = false
    @State private var appear = false
    @State private var pulseLive = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            atmosphere

            VStack(spacing: 0) {
                topChrome
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                if session.isActive {
                    liveBanner
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            if session.isActive || session.isAnalyzing {
                                LiveScreenStatusTheater(phase: session.phase, status: session.statusLine)
                                    .transition(.opacity.combined(with: .scale(0.98)))
                            }

                            floatingPreviewCard

                            if !session.sessionSummary.isEmpty {
                                summaryCard
                            }

                            if !session.suggestedActions.isEmpty {
                                suggestedActionsRow
                            }

                            qualityPicker
                            modePicker
                            if !session.turns.isEmpty {
                                conversationStack
                            }
                            Color.clear.frame(height: 8).id("bottom")
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                        .padding(.bottom, 120)
                    }
                    .onChange(of: session.turns.count) { _, _ in
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            VStack {
                Spacer()
                bottomBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
        .nocoBackground()
        .navigationBarHidden(true)
        .onAppear {
            session.bind(
                apiProvider: { connection.companionAPI() },
                speakBusy: {
                    connection.speak.isBusyForVision
                }
            )
            withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) { appear = true }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulseLive = true }
            if !session.hasConsent { showConsent = true }
        }
        .onDisappear {
            // Keep Broadcast alive if Speak still uses screen share; otherwise soft-stop in-app only.
            if session.isActive, !connection.speak.screenShareEnabled {
                session.stopInAppCapture()
            }
        }
        .sheet(isPresented: $showConsent) {
            consentSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: Binding(
            get: { session.showEndSessionSheet },
            set: { if !$0 { session.showEndSessionSheet = false } }
        )) {
            endSessionSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .alert("Live Screen", isPresented: Binding(
            get: { session.lastError != nil },
            set: { if !$0 { session.clearError() } }
        )) {
            Button("Einstellungen") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
                session.clearError()
            }
            Button("OK", role: .cancel) { session.clearError() }
        } message: {
            Text(session.lastError ?? "")
        }
    }

    private var summaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Sitzungsübersicht", systemImage: "list.bullet.rectangle")
                    .font(.subheadline.weight(.semibold))
                Text(session.sessionSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Atmosphere

    private var atmosphere: some View {
        ZStack {
            IntelligenceAtmosphere()
                .opacity(0.85)
            RadialGradient(
                colors: [
                    session.phase.color.opacity(scheme == .dark ? 0.28 : 0.16),
                    session.mode.accent.opacity(scheme == .dark ? 0.18 : 0.10),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 340
            )
            .animation(.easeInOut(duration: 0.55), value: session.phase)
            .animation(.easeInOut(duration: 0.55), value: session.mode)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Chrome

    private var topChrome: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                HapticService.soft()
                if session.isActive {
                    session.requestStopSession()
                }
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("NOCO Live Screen")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("\(session.phase.title) · \(session.statusLine)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if session.isActive {
                Button {
                    HapticService.rigid()
                    session.requestStopSession()
                } label: {
                    Text("Stop")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.9), in: Capsule())
                }
            } else {
                Button {
                    HapticService.open()
                    if session.hasConsent {
                        try? session.startSession()
                    } else {
                        showConsent = true
                    }
                } label: {
                    Text("Start")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(session.mode.accent.gradient, in: Capsule())
                }
                .disabled(!connection.isOnline)
                .opacity(connection.isOnline ? 1 : 0.5)
            }
        }
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : -8)
    }

    private var liveBanner: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .scaleEffect(pulseLive ? 1.25 : 0.85)
                .opacity(pulseLive ? 1 : 0.55)
            Text("LIVE · Bildschirmhilfe aktiv")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            if let kind = session.captureKind {
                Text(kindLabel(kind))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.red.opacity(0.35), lineWidth: 1)
                )
        }
    }

    // MARK: - Preview card

    private var floatingPreviewCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Sichtbarer Kontext", systemImage: "rectangle.inset.filled.and.person.filled")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if session.isAnalyzing {
                        ProgressView()
                            .scaleEffect(0.85)
                    }
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                        .frame(height: 200)

                    if let preview = session.latestPreview {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: session.mode.accent.opacity(0.25), radius: 16, y: 8)
                            .transition(.opacity.combined(with: .scale(0.98)))
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "sparkle.magnifyingglass")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundStyle(session.mode.accent)
                            Text("Bildschirmübertragung starten oder Screenshot teilen")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.86), value: session.latestPreview != nil)

                if !session.latestOCRPreview.isEmpty {
                    Text(session.latestOCRPreview)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                captureActions
            }
        }
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 14)
    }

    private var captureActions: some View {
        VStack(spacing: 10) {
            // Primary: system Broadcast (Control Center style)
            HStack(spacing: 12) {
                BroadcastPickerRepresentable()
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(Color.red.opacity(0.14))
                    )
                    .disabled(!session.isActive)
                    .opacity(session.isActive ? 1 : 0.45)
                    .allowsHitTesting(session.isActive)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Bildschirmübertragung")
                        .font(.subheadline.weight(.semibold))
                    Text(session.captureKind == .broadcastExtension
                          ? "Live — intelligente Frames (nur bei Änderungen)"
                          : "Wie Kontrollzentrum: App wählen, Übertragung starten")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.red.opacity(session.captureKind == .broadcastExtension ? 0.55 : 0.2), lineWidth: 1)
            )

            if session.broadcastWaiting && session.isActive {
                Text("Tipp: Kontrollzentrum → Bildschirmaufnahme → „NOCO Live Screen“, oder den roten Button tippen. Ohne Übertragung keine Analyse.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    labelChip(title: "Screenshot", icon: "photo.on.rectangle")
                }
                .disabled(!session.isActive)

                Button {
                    HapticService.light()
                    Task { _ = await session.ingestClipboardIfPossible() }
                } label: {
                    labelChip(title: "Einfügen", icon: "doc.on.clipboard")
                }
                .disabled(!session.isActive)

                Button {
                    HapticService.open()
                    Task {
                        if session.captureKind == .inAppReplay {
                            await session.captureCurrentInAppFrame()
                        } else {
                            await session.startInAppCapture()
                        }
                    }
                } label: {
                    labelChip(
                        title: session.captureKind == .inAppReplay ? "Frame" : "In-App",
                        icon: "record.circle"
                    )
                }
                .disabled(!session.isActive)
            }
        }
    }

    private func labelChip(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - Modes

    private var suggestedActionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(session.suggestedActions) { action in
                    Button {
                        HapticService.selection()
                        Task { await session.analyze(userPrompt: action.prompt) }
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .disabled(!session.isActive || session.isAnalyzing)
                }
            }
        }
    }

    private var qualityPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !session.activeModelLabel.isEmpty {
                Text("NOCO nutzt: \(session.activeModelLabel)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LiveScreenQuality.allCases) { q in
                        Button {
                            HapticService.selection()
                            session.quality = q
                        } label: {
                            Text(q.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(session.quality == q ? Color.white : Color.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background {
                                    if session.quality == q {
                                        Capsule().fill(session.phase.color.gradient)
                                    } else {
                                        Capsule().fill(.ultraThinMaterial)
                                    }
                                }
                        }
                    }
                }
            }
        }
    }

    private var modePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(LiveScreenMode.allCases) { mode in
                    Button {
                        HapticService.selection()
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            session.mode = mode
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: mode.systemImage)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(mode.title)
                                    .font(.caption.weight(.bold))
                                Text(mode.subtitle)
                                    .font(.caption2)
                                    .opacity(0.75)
                            }
                        }
                        .foregroundStyle(session.mode == mode ? Color.white : Color.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background {
                            if session.mode == mode {
                                Capsule().fill(mode.accent.gradient)
                            } else {
                                Capsule().fill(.ultraThinMaterial)
                            }
                        }
                    }
                    .buttonStyle(IntelligencePressStyle(haptic: { HapticService.soft() }))
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Conversation

    private var conversationStack: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(session.turns) { turn in
                turnBubble(turn)
                    .id(turn.id)
            }
        }
    }

    private func turnBubble(_ turn: LiveScreenTurn) -> some View {
        HStack(alignment: .top) {
            if turn.role == .user { Spacer(minLength: 40) }

            VStack(alignment: turn.role == .user ? .trailing : .leading, spacing: 6) {
                if let data = turn.thumbnailJPEG, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                Text(turn.text)
                    .font(.subheadline)
                    .foregroundStyle(turn.role == .system ? .secondary : .primary)
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(bubbleColor(for: turn.role))
                    }

                if turn.role == .assistant, !turn.text.isEmpty {
                    IntelligenceHandoffBar(
                        text: turn.text,
                        onChat: {
                            connection.continueInChat(
                                draft: "Kontext aus Live Screen:\n\n\(turn.text)\n\nBitte hilf mir weiter."
                            )
                        },
                        onSpeak: {
                            connection.speak.voice.speak(turn.text)
                            HapticService.speakCue()
                        },
                        onAgent: {
                            connection.handoffToAgent(goal: turn.text)
                        }
                    )
                }
            }

            if turn.role != .user { Spacer(minLength: 40) }
        }
    }

    private func bubbleColor(for role: LiveScreenTurn.Role) -> Color {
        switch role {
        case .user:
            return session.mode.accent.opacity(scheme == .dark ? 0.35 : 0.22)
        case .assistant:
            return scheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.72)
        case .system:
            return Color.primary.opacity(0.06)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if session.isActive {
                HStack(spacing: 10) {
                    TextField("Frage zum Bildschirm…", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($inputFocused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Button {
                        send()
                    } label: {
                        Image(systemName: session.isAnalyzing ? "hourglass" : "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(session.mode.accent)
                    }
                    .disabled(session.isAnalyzing || !connection.isOnline || session.latestPreview == nil)
                }
            }

            HStack {
                Toggle(isOn: Binding(
                    get: { session.autoAssistEnabled },
                    set: { session.autoAssistEnabled = $0 }
                )) {
                    Text("Auto-Assistent")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .labelsHidden()
                Text(session.autoAssistEnabled ? "Auto bei Änderungen" : "Nur auf Nachfrage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if connection.isOnline {
                    Label("Companion", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(NOCOAITheme.success)
                } else {
                    Label("Offline", systemImage: "wifi.slash")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 20, y: -4)
        }
    }

    // MARK: - Consent

    private var consentSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .font(.system(size: 36))
                    .foregroundStyle(session.mode.accent)
                    .padding(.top, 8)

                Text("Bildschirmhilfe mit Zustimmung")
                    .font(.title2.bold())

                Text("NOCO Live Screen analysiert nur Bilder, die du aktiv teilst oder überträgst. Es gibt kein Dauer-Video-Streaming: NOCO erkennt relevante Änderungen und analysiert gezielt. OCR läuft lokal; Analyse geht an deinen Companion. Frames bleiben standardmäßig im Speicher.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    consentBullet("Bildschirmübertragung über Kontrollzentrum")
                    consentBullet("Analyse nur bei Änderungen oder Fragen")
                    consentBullet("OCR lokal auf dem Gerät")
                    consentBullet("Kontext speichern oder löschen am Ende")
                    consentBullet("Jederzeit stoppen")
                }

                Spacer()

                Button {
                    session.grantConsent()
                    showConsent = false
                    try? session.startSession()
                } label: {
                    Text("Zustimmen & starten")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(session.mode.accent.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.white)
                }

                Button("Ablehnen") {
                    showConsent = false
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.secondary)
            }
            .padding(24)
            .navigationTitle("Datenschutz")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func consentBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(NOCOAITheme.success)
            Text(text)
                .font(.subheadline)
        }
    }

    private var endSessionSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Live Screen beenden")
                    .font(.title3.bold())
                Text("Soll der Sitzungskontext (Übersicht & Notizen) gespeichert bleiben — z. B. für „Was war auf meinem Bildschirm?“ — oder gelöscht werden?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !session.sessionSummary.isEmpty {
                    Text(session.sessionSummary)
                        .font(.footnote)
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Spacer()

                Button {
                    session.saveContextAndStop()
                    HapticService.success()
                } label: {
                    Text("Kontext speichern & beenden")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(session.mode.accent.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.white)
                }

                Button {
                    session.discardContextAndStop()
                } label: {
                    Text("Kontext löschen & beenden")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.red)
                }

                Button("Abbrechen") {
                    session.showEndSessionSheet = false
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }

    // MARK: - Actions

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        inputFocused = false
        HapticService.open()
        Task {
            await session.analyze(userPrompt: text.isEmpty ? nil : text)
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        guard session.isActive else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await session.ingest(image: image, source: .photoLibrary, autoAnalyze: true, force: true)
            }
        } catch {
            // ignore
        }
        photoItem = nil
    }

    private func kindLabel(_ kind: LiveScreenCaptureKind) -> String {
        switch kind {
        case .photoLibrary: return "Screenshot"
        case .clipboard: return "Zwischenablage"
        case .inAppReplay: return "In-App"
        case .cameraLiveVision: return "Kamera"
        case .broadcastExtension: return "Broadcast"
        case .documentScan: return "Dokument"
        case .windowsDesktop: return "Windows"
        }
    }
}
