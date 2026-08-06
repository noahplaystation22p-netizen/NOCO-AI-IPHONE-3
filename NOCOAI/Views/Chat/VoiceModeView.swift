import SwiftUI

struct VoiceModeView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private var speak: SpeakSessionController { connection.speak }
    private var voice: VoiceService { speak.voice }

    var body: some View {
        ZStack {
            IntelligenceMeshBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.bottom, 4)

                Spacer(minLength: 8)

                // Visualizer first — hero of the Speak UI
                IntelligenceVoiceStage(phase: voice.phase, level: voice.level, bands: voice.bands)
                    .frame(maxHeight: 260)
                    .padding(.horizontal, 4)

                phaseBadge
                    .padding(.top, 6)

                // Transcript / reply under the stage
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
        .task {
            _ = await voice.requestPermissions()
            if !connection.isOnline {
                speak.statusLine = "PC offline — Companion in NOCO AI X starten"
            } else if !speak.isRunning {
                speak.statusLine = "Starten → Pause sendet. Antwort bleibt hier sichtbar."
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
                    .fill(NOCOAITheme.accent.opacity(0.12))
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: voice.phase)
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
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: voice.phase)
        .animation(.easeOut(duration: 0.1), value: voice.level)
    }

    private var phaseLabel: String {
        switch voice.phase {
        case .listening: return "Du sprichst"
        case .processing: return "PC denkt"
        case .speaking: return "NOCO antwortet"
        case .error: return "Fehler"
        case .idle: return speak.isRunning ? "Bereit" : "Speak"
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
            Text(VoiceSettings.defaultMode.label)
                .font(.caption2.weight(.bold))
            if speak.isRunning {
                Text("· Live Activity")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
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
                .fill(NOCOAITheme.accent.opacity(0.15))
                .overlay(Capsule().stroke(NOCOAITheme.glowPrimary.opacity(0.35), lineWidth: 1))
        )
        .foregroundStyle(NOCOAITheme.accent)
    }

    private var displayText: String {
        switch voice.phase {
        case .listening:
            return voice.liveTranscript.isEmpty ? "Ich höre zu… sprich einfach." : voice.liveTranscript
        case .processing:
            return voice.liveTranscript.isEmpty ? "Sende an den PC…" : voice.liveTranscript
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
            }
            .disabled(!connection.isOnline && !speak.isRunning)
            .opacity(connection.isOnline || speak.isRunning ? 1 : 0.45)
        }
    }

    private var controlHint: String {
        if !connection.isOnline { return "PC offline" }
        if speak.isMuted { return "Mute an — Antworten hörst du trotzdem" }
        if speak.isRunning {
            switch voice.phase {
            case .listening: return "Pause → sendet sofort"
            case .processing: return "Warte auf PC…"
            case .speaking: return "Danach wieder Zuhören"
            default: return "Live"
            }
        }
        return "Starten für Live-Gespräch"
    }
}

enum VoiceSettings {
    static var defaultMode: AIMode {
        get {
            if let raw = UserDefaults.standard.string(forKey: "nocoai.voiceMode") {
                let mode = AIMode.from(raw)
                if raw == "normal" { return .flash }
                return mode
            }
            return .flash
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "nocoai.voiceMode")
        }
    }
}
