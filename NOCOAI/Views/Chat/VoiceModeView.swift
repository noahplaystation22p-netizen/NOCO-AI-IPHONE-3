import SwiftUI

struct VoiceModeView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var camera = VisionLiveCameraController()
    @State private var cameraOn = false
    @State private var micPulse = false

    private var speak: SpeakSessionController { connection.speak }
    private var voice: VoiceService { speak.voice }

    var body: some View {
        ZStack {
            IntelligenceMeshBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.bottom, 4)

                if cameraOn {
                    cameraPreview
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer(minLength: 8)

                ZStack {
                    if !cameraOn {
                        IntelligenceVoiceStage(phase: voice.phase, level: voice.level, bands: voice.bands)
                            .frame(maxHeight: 280)
                            .padding(.horizontal, 4)
                            .padding(.top, 6)
                    } else {
                        compactVoiceMeter
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.84), value: cameraOn)

                phaseBadge
                    .padding(.top, 6)

                if let pending = speak.pendingToolConfirm {
                    confirmBanner(pending)
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                promptPanel
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text(speak.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                modeChip
                    .padding(.top, 10)

                controls
                    .padding(.top, 16)
                    .padding(.bottom, 30)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: cameraOn)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: voice.phase)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: speak.assistantPhase)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: speak.pendingToolConfirm != nil)
        .task {
            _ = await voice.requestPermissions()
            if !connection.isOnline {
                speak.statusLine = "PC offline — Companion in NOCO AI X starten"
            } else if !speak.isRunning {
                speak.statusLine = "Rede aus — danach verarbeitet NOCO und antwortet."
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
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                micPulse = true
            }
        }
    }

    private var cameraPreview: some View {
        ZStack(alignment: .topTrailing) {
            VisionLiveCameraPreview(session: camera.session)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.45, green: 0.72, blue: 1),
                                    Color(red: 0.95, green: 0.55, blue: 0.78),
                                    Color(red: 0.45, green: 0.85, blue: 0.9)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.4
                        )
                )
                .shadow(color: Color(red: 0.45, green: 0.72, blue: 1).opacity(0.35), radius: 16, y: 6)

            HStack(spacing: 8) {
                Label("Vision aktiv", systemImage: "eye.fill")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                Button {
                    Task { await camera.flipCamera() }
                } label: {
                    Image(systemName: "camera.rotate.fill")
                        .font(.caption.weight(.bold))
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(12)
        }
    }

    private var compactVoiceMeter: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.35, green: 0.8, blue: 1).opacity(0.9),
                            Color(red: 0.55, green: 0.45, blue: 1).opacity(0.35),
                            .clear
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: 28
                    )
                )
                .frame(width: 52, height: 52)
                .scaleEffect(micPulse && voice.phase == .listening ? 1.12 : 1)
                .overlay(
                    Image(systemName: speak.isMuted ? "mic.slash.fill" : "mic.fill")
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(phaseLabel)
                    .font(.subheadline.weight(.semibold))
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.35, green: 0.8, blue: 1),
                                            Color(red: 0.55, green: 0.45, blue: 1)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(8, geo.size.width * CGFloat(max(0.08, voice.level))))
                        }
                }
                .frame(height: 6)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
    }

    private var phaseBadge: some View {
        Text(phaseLabel)
            .font(.caption.weight(.bold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(NOCOAITheme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(NOCOAITheme.accent.opacity(0.12 + Double(voice.level) * 0.18))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(NOCOAITheme.accent.opacity(0.25 + Double(voice.level) * 0.45), lineWidth: 1)
                    )
            )
            .scaleEffect(1 + voice.level * (voice.phase == .listening ? 0.08 : 0.03))
            .animation(.easeOut(duration: 0.06), value: voice.level)
    }

    private var promptPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(displayText)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("promptBottom")
                        .contentTransition(.opacity)
                }
                .padding(18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.4, green: 0.85, blue: 1).opacity(0.5),
                                        Color(red: 0.55, green: 0.9, blue: 0.85).opacity(0.35),
                                        Color(red: 0.4, green: 0.85, blue: 1).opacity(0.45)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .onChange(of: displayText) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("promptBottom", anchor: .bottom)
                }
            }
        }
    }

    private var phaseLabel: String {
        if speak.pendingToolConfirm != nil { return "Bestätigung" }
        switch speak.assistantPhase {
        case .creatingImage: return "NOCO erstellt dein Bild…"
        case .agentWorking: return "NOCO arbeitet…"
        case .webSearch: return "NOCO sucht im Internet…"
        case .vision: return cameraOn || speak.screenShareEnabled ? "NOCO sieht…" : "Analysiert"
        case .thinking: return "NOCO denkt…"
        case .awaitingConfirm: return "Bestätigung"
        case .speaking: return "NOCO antwortet"
        case .error: return "Fehler"
        case .listening, .idle:
            break
        }
        if cameraOn {
            switch voice.phase {
            case .listening: return "Hören + Sehen"
            case .processing: return "Verstehe Szene"
            case .speaking: return "NOCO antwortet"
            case .error: return "Fehler"
            case .idle: return speak.isRunning ? "Kamera bereit" : "Speak"
            }
        }
        switch voice.phase {
        case .listening: return "NOCO hört zu"
        case .processing: return "NOCO denkt…"
        case .speaking: return "NOCO antwortet"
        case .error: return "Fehler"
        case .idle: return speak.isRunning ? "Assistent bereit" : "Speak"
        }
    }

    private var topBar: some View {
        HStack {
            Button(speak.isRunning ? "Im Hintergrund lassen" : "Fertig") {
                dismiss()
                speak.showSpeakUI = false
            }
            .fontWeight(.medium)

            Spacer()

            HStack(spacing: 6) {
                IntelligencePulseDot(
                    color: connection.isOnline ? NOCOAITheme.success : NOCOAITheme.danger,
                    size: 7
                )
                Text(connection.isOnline ? "NOCO Sync" : "Offline")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(connection.isOnline ? NOCOAITheme.success : NOCOAITheme.danger)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var modeChip: some View {
        HStack(spacing: 8) {
            Text(SpeakFullAccess.isEnabled ? "Assistent" : "Sicher")
                .font(.caption2.weight(.bold))
            if speak.isRunning {
                Text("· Live")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            switch speak.assistantPhase {
            case .creatingImage:
                Text("· Bild").font(.caption2.weight(.bold)).foregroundStyle(NOCORainbow.pink)
            case .agentWorking:
                Text("· Agent").font(.caption2.weight(.bold)).foregroundStyle(NOCORainbow.teal)
            case .webSearch:
                Text("· Web").font(.caption2.weight(.bold)).foregroundStyle(Color(red: 0.35, green: 0.62, blue: 1))
            case .vision:
                Text("· Vision").font(.caption2.weight(.bold)).foregroundStyle(NOCORainbow.blue)
            case .thinking:
                Text("· Think").font(.caption2.weight(.bold)).foregroundStyle(NOCORainbow.violet)
            default:
                EmptyView()
            }
            if cameraOn {
                Text("· Kamera")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(red: 0.45, green: 0.72, blue: 1))
            }
            if speak.isMuted {
                Text("MUTE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule().stroke(
                        AngularGradient(colors: NOCORainbow.flow.map { $0.opacity(0.55) }, center: .center),
                        lineWidth: 1
                    )
                )
        )
        .foregroundStyle(NOCOAITheme.accent)
    }

    private func confirmBanner(_ intent: SpeakIntent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                NOCOIntelligenceCore(energy: .thinking, size: .compact, systemImage: "questionmark")
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bestätigung")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(intent.confirmationQuestion)
                        .font(.subheadline.weight(.semibold))
                }
            }
            Text("Sag „Ja“ zum Starten oder „Nein“ zum Abbrechen.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AngularGradient(colors: NOCORainbow.flow.map { $0.opacity(0.4) }, center: .center), lineWidth: 1)
                )
        }
    }

    private var displayText: String {
        switch voice.phase {
        case .listening:
            return voice.liveTranscript.isEmpty
                ? (cameraOn ? "Ich höre und sehe… frag einfach „Was ist das?“." : "Ich höre zu… sprich einfach.")
                : voice.liveTranscript
        case .processing:
            return voice.liveTranscript.isEmpty
                ? (cameraOn ? "Schaue und denke…" : "Sende an den PC…")
                : voice.liveTranscript
        case .speaking:
            return speak.lastReply.isEmpty ? "Antwort wird gesprochen…" : speak.lastReply
        case .error(let msg):
            return msg
        case .idle:
            return speak.lastReply.isEmpty ? "Tippe Starten und frag mich etwas." : speak.lastReply
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Text(controlHint)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Button {
                Task { await toggleCamera() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: cameraOn ? "eye.slash.fill" : "camera.fill")
                    Text(cameraOn ? "Kamera aus" : "📷 Kamera")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(cameraOn ? Color(red: 0.45, green: 0.72, blue: 1) : .primary)
                .frame(width: 240, height: 44)
                .background(
                    Capsule()
                        .fill(cameraOn
                              ? Color(red: 0.45, green: 0.72, blue: 1).opacity(0.18)
                              : Color.primary.opacity(0.08))
                )
            }
            .disabled(!connection.isOnline && !cameraOn)

            Button {
                Task { await toggleScreenShare() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: speak.screenShareEnabled ? "rectangle.slash" : "rectangle.inset.filled.and.person.filled")
                    Text(speak.screenShareEnabled ? "Bildschirm aus" : "🖥 Bildschirm teilen")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(speak.screenShareEnabled ? Color(red: 0.98, green: 0.45, blue: 0.4) : .primary)
                .frame(width: 240, height: 44)
                .background(
                    Capsule()
                        .fill(speak.screenShareEnabled
                              ? Color.red.opacity(0.14)
                              : Color.primary.opacity(0.08))
                )
            }
            .disabled(!connection.isOnline && !speak.screenShareEnabled)

            if cameraOn || speak.screenShareEnabled {
                Button {
                    speak.captureVisionSnapshot()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "viewfinder")
                        Text(speak.pendingVisionJPEG == nil ? "Momentaufnahme" : "Aufnahme bereit ✓")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.primary)
                    .frame(width: 240, height: 44)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            }

            if speak.isRunning {
                Button {
                    HapticService.toggle()
                    speak.toggleMute()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: speak.isMuted ? "mic.slash.fill" : "mic.fill")
                        Text(speak.isMuted ? "Mute aus · wieder sprechen" : "Mute · nur zuhören")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(speak.isMuted ? .orange : .primary)
                    .frame(width: 240, height: 44)
                    .background(
                        Capsule()
                            .fill(speak.isMuted ? Color.orange.opacity(0.18) : Color.primary.opacity(0.08))
                            .overlay(
                                Capsule().stroke(
                                    speak.isMuted ? Color.orange.opacity(0.5) : Color.clear,
                                    lineWidth: 1
                                )
                            )
                    )
                }
            }

            Button {
                if speak.isRunning {
                    HapticService.speakCue()
                    speak.stop()
                } else {
                    HapticService.send()
                    speak.start()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: speak.isRunning ? "stop.fill" : "waveform")
                        .font(.title3.weight(.semibold))
                        .symbolEffect(.variableColor.iterative, isActive: speak.isRunning && !reduceMotion)
                    Text(speak.isRunning ? "Stoppen" : "Speak starten")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: 228, height: 58)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: speak.isRunning
                                    ? [Color.red.opacity(0.85), Color.orange.opacity(0.75)]
                                    : [
                                        Color(red: 0.35, green: 0.72, blue: 1),
                                        Color(red: 0.45, green: 0.85, blue: 0.9)
                                    ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .shadow(color: Color(red: 0.4, green: 0.7, blue: 1).opacity(0.4), radius: 14)
                .scaleEffect(speak.isRunning && voice.phase == .listening && micPulse ? 1.02 : 1)
            }
            .disabled(!connection.isOnline && !speak.isRunning)
            .opacity(connection.isOnline || speak.isRunning ? 1 : 0.45)
        }
    }

    private var controlHint: String {
        if !connection.isOnline { return "PC offline" }
        if speak.pendingToolConfirm != nil { return "Sag Ja oder Nein" }
        if speak.screenShareEnabled { return "Bildschirm an — frag „Was soll ich tippen?“" }
        if cameraOn { return "Kamera an — „Was sehe ich?“ analysiert die Szene" }
        if speak.isMuted { return "Mute an — Antworten hörst du trotzdem" }
        if speak.isRunning {
            switch speak.assistantPhase {
            case .creatingImage: return "Bildmodell arbeitet…"
            case .agentWorking: return "Agent erledigt die Aufgabe…"
            case .webSearch: return "Live Knowledge · ich hole aktuelle Infos…"
            case .vision: return "Vision analysiert…"
            case .thinking: return "NOCO denkt nach…"
            case .awaitingConfirm: return "Bestätigung nötig"
            default: break
            }
            switch voice.phase {
            case .listening: return SpeakFullAccess.isEnabled
                ? "Rede natürlich — Tools starten automatisch"
                : "Rede natürlich — bei Tools fragt NOCO kurz"
            case .processing: return "Einen Moment…"
            case .speaking: return "Danach wieder Zuhören"
            default: return "Live"
            }
        }
        return "Starten · persönlicher KI-Assistent"
    }

    private func toggleCamera() async {
        if cameraOn {
            camera.stop()
            cameraOn = false
            speak.visionCameraEnabled = false
            speak.visionFrameProvider = nil
            speak.pendingVisionJPEG = nil
            speak.statusLine = speak.isRunning ? "Kamera aus · nur Sprache" : "Speak bereit"
            HapticService.soft()
            return
        }
        // Prefer one visual source at a time
        if speak.screenShareEnabled {
            speak.disableScreenShare()
        }
        await camera.requestAccessAndStart()
        guard !camera.permissionDenied else {
            speak.statusLine = "Kamera-Berechtigung fehlt — in Einstellungen erlauben"
            HapticService.error()
            return
        }
        cameraOn = true
        speak.visionCameraEnabled = true
        speak.visionFrameProvider = { camera.latestFrame }
        speak.pendingVisionJPEG = nil
        speak.statusLine = "Kamera bereit — Momentaufnahme oder frag „Was ist das?“"
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

enum VoiceSettings {
    static var defaultMode: AIMode {
        get {
            // Legacy key — Speak depth is chosen by SpeakIntentEngine now.
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
