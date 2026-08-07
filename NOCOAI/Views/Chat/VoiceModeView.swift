import SwiftUI

/// NOCO Voice AI — Apple Intelligence–inspired system assistant surface.
struct VoiceModeView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var camera = VisionLiveCameraController()
    @State private var cameraOn = false
    @State private var titlePulse = false

    private var speak: SpeakSessionController { connection.speak }
    private var voice: VoiceService { speak.voice }

    var body: some View {
        ZStack {
            IntelligenceMeshBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.bottom, 2)

                if cameraOn {
                    cameraPreview
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96)),
                            removal: .opacity
                        ))
                }

                Spacer(minLength: cameraOn ? 6 : 12)

                // Living KI hero
                ZStack {
                    if !cameraOn {
                        IntelligenceVoiceStage(
                            phase: voice.phase,
                            level: voice.level,
                            bands: voice.bands,
                            assistantPhase: speak.assistantPhase
                        )
                        .frame(maxHeight: 300)
                        .padding(.horizontal, 8)
                    } else {
                        compactHeroMeter
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.86), value: cameraOn)

                animatedPhaseTitle
                    .padding(.top, cameraOn ? 10 : 4)
                    .padding(.horizontal, 24)

                if let pending = speak.pendingToolConfirm {
                    confirmBanner(pending)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                glassTranscript
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                iconControls
                    .padding(.top, 18)
                    .padding(.bottom, 8)

                primaryControl
                    .padding(.bottom, 28)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: cameraOn)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: voice.phase)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: speak.assistantPhase)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: speak.pendingToolConfirm != nil)
        .task {
            _ = await voice.requestPermissions()
            if !connection.isOnline {
                speak.statusLine = "PC offline — Companion starten"
            } else if !speak.isRunning {
                speak.statusLine = "Voice AI starten — dann natürlich sprechen"
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if speak.isRunning {
                if phase != .active {
                    speak.ensureBackgroundPresence()
                } else {
                    speak.pushLiveActivity(force: true)
                }
            }
        }
        .onDisappear {
            if cameraOn {
                camera.stop()
                cameraOn = false
                speak.visionCameraEnabled = false
                speak.visionFrameProvider = nil
            }
        }
        .onChange(of: speak.visionCameraEnabled) { _, enabled in
            if !enabled, cameraOn {
                camera.stop()
                cameraOn = false
            }
        }
        .onChange(of: speak.showSpeakUI) { _, show in
            if !show, cameraOn {
                camera.stop()
                cameraOn = false
                speak.visionFrameProvider = nil
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                titlePulse = true
            }
        }
    }

    // MARK: - Top

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
                speak.showSpeakUI = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(speak.isRunning ? "Im Hintergrund lassen" : "Schließen")

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(connection.isOnline ? Color.green : Color.red)
                    .frame(width: 7, height: 7)
                    .shadow(color: (connection.isOnline ? Color.green : Color.red).opacity(0.6), radius: 4)
                Text(connection.isOnline ? "Live" : "Offline")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    // MARK: - Phase title (animated typography)

    private var animatedPhaseTitle: some View {
        Text(phaseLabel)
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        NOCORainbow.blue,
                        NOCORainbow.violet,
                        NOCORainbow.pink
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .shadow(color: NOCORainbow.violet.opacity(titlePulse ? 0.45 : 0.15), radius: titlePulse ? 14 : 6)
            .scaleEffect(titlePulse && speak.isRunning ? 1.02 : 1)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.35), value: phaseLabel)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Camera

    private var cameraPreview: some View {
        ZStack(alignment: .topTrailing) {
            VisionLiveCameraPreview(session: camera.session)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(
                            AngularGradient(colors: NOCORainbow.flow.map { $0.opacity(0.7) }, center: .center),
                            lineWidth: 1.4
                        )
                )
                .shadow(color: NOCORainbow.blue.opacity(0.3), radius: 18, y: 8)

            Button {
                Task { await camera.flipCamera() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(12)
        }
    }

    private var compactHeroMeter: some View {
        HStack(spacing: 16) {
            NOCOIntelligenceCore(
                energy: speakEnergy,
                size: .medium,
                level: voice.level,
                systemImage: speak.isMuted ? "mic.slash.fill" : "eye.fill"
            )
            .frame(width: 88, height: 88)

            VStack(alignment: .leading, spacing: 8) {
                Text(cameraOn ? "Vision + Sprache" : "Bereit")
                    .font(.subheadline.weight(.semibold))
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [NOCORainbow.blue, NOCORainbow.violet],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(10, geo.size.width * CGFloat(max(0.08, voice.level))))
                        }
                }
                .frame(height: 7)
            }
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Transcript (living glass)

    private var transcriptStyle: VoiceTranscriptStyle {
        if speak.pendingToolConfirm != nil { return .thinking }
        switch speak.assistantPhase {
        case .thinking, .webSearch, .creatingImage, .agentWorking, .vision, .awaitingConfirm:
            return .thinking
        case .speaking:
            return .speaking
        case .listening:
            return .listening
        case .error, .idle:
            break
        }
        switch voice.phase {
        case .listening: return .listening
        case .processing: return .thinking
        case .speaking: return .speaking
        case .idle, .error: return speak.isRunning ? .listening : .idle
        }
    }

    private var glassTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    if transcriptStyle == .listening, speak.isRunning {
                        // Soft reactive audio cue above live speech
                        SpeakVoiceMiniMeter(level: voice.level, bands: voice.bands)
                            .frame(height: 18)
                            .padding(.horizontal, 40)
                            .opacity(0.85)
                    }

                    VoiceLivingTranscript(
                        text: displayText,
                        style: transcriptStyle,
                        level: voice.level
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .id("speakBottom")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(18)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.14),
                                    transcriptStyle == .speaking
                                        ? NOCORainbow.violet.opacity(0.08)
                                        : NOCORainbow.blue.opacity(0.05),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(
                            AngularGradient(
                                colors: NOCORainbow.flow.map {
                                    $0.opacity(transcriptStyle == .thinking ? 0.55 : 0.32)
                                },
                                center: .center
                            ),
                            lineWidth: 1.2
                        )
                }
                .shadow(
                    color: (transcriptStyle == .speaking ? NOCORainbow.violet : NOCORainbow.blue)
                        .opacity(0.16),
                    radius: 22,
                    y: 8
                )
            }
            .animation(.easeInOut(duration: 0.35), value: transcriptStyle)
            .onChange(of: displayText) { _, _ in
                // Soft scroll — no layout jump / zoom fight with transcript text.
                proxy.scrollTo("speakBottom", anchor: .bottom)
            }
        }
    }

    // MARK: - Icon controls

    private var iconControls: some View {
        HStack(spacing: 22) {
            SpeakIconButton(
                systemImage: cameraOn ? "camera.fill" : "camera",
                active: cameraOn,
                tint: NOCORainbow.blue,
                label: "Kamera"
            ) {
                Task { await toggleCamera() }
            }
            .disabled(!connection.isOnline && !cameraOn)

            SpeakIconButton(
                systemImage: speak.screenShareEnabled
                    ? "rectangle.inset.filled.and.person.filled"
                    : "rectangle.dashed",
                active: speak.screenShareEnabled,
                tint: NOCORainbow.teal,
                label: "Bildschirm",
                analyzing: speak.screenShareEnabled && speak.assistantPhase == .vision
            ) {
                Task { await toggleScreenShare() }
            }
            .disabled(!connection.isOnline && !speak.screenShareEnabled)

            SpeakIconButton(
                systemImage: speak.isMuted ? "mic.slash.fill" : "mic.fill",
                active: speak.isMuted,
                tint: .orange,
                label: "Stumm",
                enabled: speak.isRunning
            ) {
                HapticService.toggle()
                speak.toggleMute()
            }
            .opacity(speak.isRunning ? 1 : 0.35)
            .disabled(!speak.isRunning)

            if cameraOn || speak.screenShareEnabled {
                SpeakIconButton(
                    systemImage: speak.pendingVisionJPEG == nil ? "viewfinder" : "checkmark.circle.fill",
                    active: speak.pendingVisionJPEG != nil,
                    tint: NOCORainbow.pink,
                    label: "Snapshot"
                ) {
                    speak.captureVisionSnapshot()
                    HapticService.selection()
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: cameraOn || speak.screenShareEnabled)
    }

    private var primaryControl: some View {
        Button {
            if speak.isRunning {
                speak.exitSpeakToChat()
            } else {
                HapticService.send()
                speak.start()
            }
        } label: {
            ZStack {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: speak.isRunning
                                ? [Color.red.opacity(0.9), Color.orange.opacity(0.75)]
                                : [NOCORainbow.blue, NOCORainbow.violet, NOCORainbow.teal],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 168, height: 54)
                    .shadow(
                        color: (speak.isRunning ? Color.red : NOCORainbow.blue).opacity(0.4),
                        radius: 16,
                        y: 4
                    )

                HStack(spacing: 10) {
                    Image(systemName: speak.isRunning ? "stop.fill" : "waveform")
                        .font(.title3.weight(.semibold))
                        .symbolEffect(.variableColor.iterative, isActive: speak.isRunning && !reduceMotion)
                    Text(speak.isRunning ? "Stop" : "Start")
                        .font(.subheadline.weight(.bold))
                        .tracking(0.4)
                }
                .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(!connection.isOnline && !speak.isRunning)
        .opacity(connection.isOnline || speak.isRunning ? 1 : 0.4)
        .accessibilityLabel(speak.isRunning ? "Voice AI stoppen" : "Voice AI starten")
    }

    private func confirmBanner(_ intent: SpeakIntent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                NOCOIntelligenceCore(energy: .thinking, size: .compact, systemImage: "questionmark")
                    .frame(width: 36, height: 36)
                Text(intent.confirmationQuestion)
                    .font(.subheadline.weight(.semibold))
            }
            Text("Sag „Ja“ oder „Nein“")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AngularGradient(colors: NOCORainbow.flow.map { $0.opacity(0.4) }, center: .center), lineWidth: 1)
                )
        }
    }

    // MARK: - Copy / energy

    private var speakEnergy: NOCOIntelligenceEnergy {
        switch speak.assistantPhase {
        case .webSearch: return .webSearch
        case .creatingImage, .agentWorking: return .working
        case .vision: return .vision
        case .thinking: return .thinking
        case .speaking: return .speaking
        case .listening: return .listening
        case .awaitingConfirm: return .thinking
        case .error, .idle: break
        }
        switch voice.phase {
        case .listening: return .listening
        case .processing: return .thinking
        case .speaking: return .speaking
        default: return .idle
        }
    }

    private var phaseLabel: String {
        if speak.pendingToolConfirm != nil { return "Bestätigung" }
        switch speak.assistantPhase {
        case .creatingImage: return "NOCO erstellt dein Bild…"
        case .agentWorking: return "NOCO arbeitet…"
        case .webSearch: return "NOCO sucht im Internet…"
        case .vision: return "NOCO sieht…"
        case .thinking: return "NOCO denkt…"
        case .awaitingConfirm: return "Bestätigung"
        case .speaking: return "NOCO antwortet"
        case .error: return "Fehler"
        case .listening, .idle: break
        }
        if cameraOn {
            switch voice.phase {
            case .listening: return "Hören + Sehen"
            case .processing: return "Verstehe Szene"
            case .speaking: return "NOCO antwortet"
            default: return speak.isRunning ? "Vision bereit" : "Voice AI"
            }
        }
        switch voice.phase {
        case .listening: return "NOCO hört zu"
        case .processing: return "NOCO denkt…"
        case .speaking: return "NOCO antwortet"
        case .error: return "Fehler"
        case .idle: return speak.isRunning ? "Bereit" : "NOCO Voice AI"
        }
    }

    private var displayText: String {
        switch voice.phase {
        case .listening:
            return voice.liveTranscript.isEmpty
                ? (cameraOn
                   ? "Frag z. B. „Was sehe ich?“"
                   : (speak.isRunning ? "Rede natürlich…" : "Tippe Start und sprich."))
                : voice.liveTranscript
        case .processing:
            return voice.liveTranscript.isEmpty ? "Einen Moment…" : voice.liveTranscript
        case .speaking:
            return speak.lastReply.isEmpty ? "…" : speak.lastReply
        case .error(let msg):
            return msg
        case .idle:
            return speak.lastReply.isEmpty
                ? (connection.isOnline ? "Dein persönlicher Assistent." : "PC offline.")
                : speak.lastReply
        }
    }

    // MARK: - Actions

    private func toggleCamera() async {
        if cameraOn {
            camera.stop()
            cameraOn = false
            speak.visionCameraEnabled = false
            speak.visionFrameProvider = nil
            speak.pendingVisionJPEG = nil
            speak.statusLine = speak.isRunning ? "Kamera aus" : "Voice AI bereit"
            HapticService.soft()
            return
        }
        if speak.screenShareEnabled {
            speak.disableScreenShare()
        }
        await camera.requestAccessAndStart()
        guard !camera.permissionDenied else {
            speak.statusLine = "Kamera-Berechtigung fehlt"
            HapticService.error()
            return
        }
        cameraOn = true
        speak.visionCameraEnabled = true
        speak.visionFrameProvider = { camera.latestFrame }
        speak.pendingVisionJPEG = nil
        speak.statusLine = "Kamera bereit"
        HapticService.success()
    }

    private func toggleScreenShare() async {
        if speak.screenShareEnabled {
            speak.disableScreenShare()
            return
        }
        if cameraOn {
            camera.stop()
            cameraOn = false
            speak.visionCameraEnabled = false
            speak.visionFrameProvider = nil
        }
        await speak.enableScreenShare()
    }
}

// MARK: - Animated icon control

private struct SpeakIconButton: View {
    var systemImage: String
    var active: Bool
    var tint: Color
    var label: String
    var analyzing: Bool = false
    var enabled: Bool = true
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glow = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(active ? tint.opacity(0.22) : Color.primary.opacity(0.06))
                        .frame(width: 52, height: 52)
                        .overlay(
                            Circle()
                                .stroke(
                                    active
                                        ? AngularGradient(colors: NOCORainbow.flow.map { $0.opacity(0.75) }, center: .center)
                                        : AngularGradient(colors: [Color.primary.opacity(0.12)], center: .center),
                                    lineWidth: active ? 1.4 : 1
                                )
                        )
                        .shadow(color: active ? tint.opacity(glow ? 0.55 : 0.25) : .clear, radius: glow ? 12 : 6)

                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(active ? tint : .primary.opacity(0.75))
                        .symbolEffect(.bounce, value: active)
                        .symbolEffect(.pulse, options: .repeating, isActive: analyzing && !reduceMotion)
                }

                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(active ? tint : .secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .onAppear {
            guard !reduceMotion, active || analyzing else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
        .onChange(of: active) { _, on in
            if on, !reduceMotion {
                glow = false
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    glow = true
                }
            } else {
                glow = false
            }
        }
    }
}

enum VoiceSettings {
    static var defaultMode: AIMode {
        get {
            if let raw = UserDefaults.standard.string(forKey: "nocoai.voiceMode") {
                let mode = AIMode.from(raw)
                if mode == .flash || mode == .knowledge { return .flash }
            }
            return .flash
        }
        set {
            UserDefaults.standard.set(AIMode.flash.rawValue, forKey: "nocoai.voiceMode")
        }
    }
}
