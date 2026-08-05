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

            VStack(spacing: 16) {
                topBar
                titleBlock
                IntelligenceShimmerLine()
                    .padding(.horizontal, 48)

                IntelligenceVoiceStage(phase: voice.phase, level: voice.level, bands: voice.bands)
                    .padding(.top, 8)

                Text(displayText)
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 28)
                    .frame(minHeight: 64)
                    .animation(.easeOut(duration: 0.12), value: displayText)
                    .animation(.easeOut(duration: 0.08), value: voice.level)

                Text(speak.statusLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                modeChip

                Spacer()
                controls
                    .padding(.bottom, 36)
            }
        }
        .task {
            _ = await voice.requestPermissions()
            if !connection.isOnline {
                speak.statusLine = "PC offline — Companion in NOCO AI X starten"
            } else if !speak.isRunning {
                speak.statusLine = "Starten → Pause sendet automatisch.\nWeiterhören in Dynamic Island / Sperrbildschirm."
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

    private var topBar: some View {
        HStack {
            Button(speak.isRunning ? "Im Hintergrund lassen" : "Fertig") {
                // Keep session alive when running — only close UI
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
                Text(connection.isOnline ? "Intelligence Sync" : "Offline")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(connection.isOnline ? NOCOAITheme.success : NOCOAITheme.danger)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var titleBlock: some View {
        VStack(spacing: 4) {
            Text("Speak")
                .font(.largeTitle.weight(.bold))
            Text(speak.isRunning ? "Live · nur Sprache · Visualizer" : "Sprich. Dein PC denkt.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
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
                .overlay(Capsule().stroke(NOCOAITheme.glowPrimary.opacity(0.4), lineWidth: 1))
        )
        .foregroundStyle(NOCOAITheme.accent)
    }

    private var displayText: String {
        switch voice.phase {
        case .listening:
            return voice.liveTranscript.isEmpty ? "Ich höre zu…" : voice.liveTranscript
        case .processing:
            return voice.liveTranscript.isEmpty ? "Sende an den PC…" : voice.liveTranscript
        case .speaking:
            return speak.lastReply.isEmpty ? "Antwort…" : speak.lastReply
        case .error(let msg):
            return msg
        case .idle:
            return speak.lastReply.isEmpty ? "Frag mich etwas" : speak.lastReply
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Text(controlHint)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if speak.isRunning {
                Button {
                    HapticService.selection()
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
                HapticService.medium()
                if speak.isRunning {
                    speak.stop()
                } else {
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
                .frame(width: 220, height: 58)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: speak.isRunning
                                    ? [Color.red.opacity(0.85), Color.orange.opacity(0.75)]
                                    : [
                                        Color(red: 0.35, green: 0.75, blue: 1),
                                        Color(red: 0.55, green: 0.4, blue: 1),
                                        Color(red: 0.95, green: 0.4, blue: 0.75)
                                    ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: Color(red: 0.5, green: 0.45, blue: 1).opacity(0.45), radius: 18)
                )
            }
            .disabled(!connection.isOnline && !speak.isRunning)
            .opacity(connection.isOnline || speak.isRunning ? 1 : 0.4)

            if voice.phase == .speaking {
                Button("Antwort überspringen") {
                    voice.stopSpeaking(notifyFinished: true)
                }
                .font(.footnote.weight(.medium))
            }
        }
    }

    private var controlHint: String {
        if !connection.isOnline { return "Keine Verbindung" }
        if speak.isRunning {
            if speak.isMuted { return "Stumm: Mic aus — Antwort wird trotzdem vorgelesen" }
            switch voice.phase {
            case .listening: return "Leiser = Pause → sendet automatisch"
            case .processing: return "Nur Text-Antwort — keine Bilder"
            case .speaking: return "Wiedergabe · danach wieder Zuhören"
            default: return "Live Activity auf Sperrbildschirm + Island"
            }
        }
        return "Startet Live Activity + Zuhören"
    }
}

enum VoiceSettings {
    static var defaultMode: AIMode {
        get {
            if let raw = UserDefaults.standard.string(forKey: "nocoai.voiceMode") {
                let mode = AIMode.from(raw)
                // Legacy Klar → keep Flash as Speak default
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
