import SwiftUI

struct VoiceModeView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var voice = VoiceService()

    @State private var statusLine = "Gedrückt halten und sprechen"
    @State private var lastReply = ""
    @State private var isHolding = false

    var body: some View {
        ZStack {
            IntelligenceMeshBackground()

            VStack(spacing: 16) {
                topBar
                titleBlock
                IntelligenceShimmerLine()
                    .padding(.horizontal, 48)

                IntelligenceVoiceStage(phase: voice.phase, level: voice.level)
                    .padding(.top, 8)

                Text(displayText)
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 28)
                    .frame(minHeight: 64)
                    .animation(.easeOut(duration: 0.2), value: displayText)

                Text(statusLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                modeChip

                Spacer()
                holdButton
                    .padding(.bottom, 40)
            }
        }
        .task {
            let ok = await voice.requestPermissions()
            if !ok {
                statusLine = "Mikrofon & Spracherkennung erlauben"
            } else if !connection.isOnline {
                statusLine = "PC offline — Companion in NOCO AI X starten"
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button("Fertig") {
                voice.stopSpeaking()
                voice.stopListening(cancel: true)
                dismiss()
            }
            .fontWeight(.medium)

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(connection.isOnline ? NOCOAITheme.success : NOCOAITheme.danger)
                    .frame(width: 8, height: 8)
                    .shadow(color: connection.isOnline ? NOCOAITheme.success.opacity(0.7) : .clear, radius: 4)
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
            Text("Sprich. Dein PC denkt.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var modeChip: some View {
        Text(VoiceSettings.defaultMode.label)
            .font(.caption2.weight(.bold))
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
            return lastReply.isEmpty ? "Antwort…" : lastReply
        case .error(let msg):
            return msg
        case .idle:
            return lastReply.isEmpty ? "Frag mich etwas" : lastReply
        }
    }

    private var holdButton: some View {
        VStack(spacing: 12) {
            Text(holdLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ZStack {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .frame(width: 220, height: 64)
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.4, green: 0.8, blue: 1),
                                        Color(red: 0.65, green: 0.4, blue: 1),
                                        Color(red: 0.4, green: 0.95, blue: 0.7)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: isHolding ? 2 : 1.2
                            )
                    )
                    .shadow(color: Color(red: 0.5, green: 0.5, blue: 1).opacity(isHolding ? 0.45 : 0.2), radius: isHolding ? 20 : 10)

                HStack(spacing: 10) {
                    Image(systemName: isHolding ? "waveform" : "mic.fill")
                        .font(.title3.weight(.semibold))
                    Text(isHolding ? "Zuhören…" : "Gedrückt halten")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.primary)
            }
            .scaleEffect(isHolding ? 1.04 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isHolding)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isHolding else { return }
                        isHolding = true
                        startHold()
                    }
                    .onEnded { _ in
                        isHolding = false
                        Task { await endHoldAndSend() }
                    }
            )
            .disabled(!connection.isOnline || connection.chat.isSending)
            .opacity(connection.isOnline && !connection.chat.isSending ? 1 : 0.4)

            if voice.phase == .speaking {
                Button("Stoppen") {
                    voice.stopSpeaking()
                    statusLine = "Gestoppt"
                }
                .font(.footnote.weight(.medium))
            }
        }
    }

    private var holdLabel: String {
        switch voice.phase {
        case .listening: return "Loslassen zum Senden"
        case .processing: return "\(VoiceSettings.defaultMode.label) auf dem PC…"
        case .speaking: return "Spoken Reply"
        default:
            return connection.isOnline ? "Speak aktivieren" : "Keine Verbindung"
        }
    }

    private func startHold() {
        guard connection.isOnline, !connection.chat.isSending else {
            statusLine = "PC offline — erst verbinden"
            isHolding = false
            return
        }
        voice.stopSpeaking()
        do {
            try voice.startListening()
            statusLine = "Listening…"
            HapticService.rigid()
        } catch {
            statusLine = "Mikrofon-Fehler"
            voice.phase = .error(error.localizedDescription)
            isHolding = false
        }
    }

    private func endHoldAndSend() async {
        let text = voice.finishUtterance()
        guard !text.isEmpty else {
            statusLine = "Nichts erkannt — nochmal halten"
            voice.phase = .idle
            return
        }
        guard connection.isOnline else {
            statusLine = "Keine Verbindung zum PC"
            voice.phase = .error("Offline")
            return
        }

        statusLine = "Intelligence Sync…"
        voice.phase = .processing
        HapticService.send()

        let reply = await connection.chat.sendAndReturnReply(text, modeOverride: VoiceSettings.defaultMode)

        if let reply, !reply.isEmpty {
            lastReply = reply
            if voice.autoSpeakReplies {
                statusLine = "Spoken Reply…"
                voice.speak(reply)
            } else {
                voice.phase = .idle
                statusLine = "Fertig — Antwort im Chat"
            }
        } else {
            let msg = connection.chat.lastError ?? "Keine Antwort vom PC"
            statusLine = msg
            voice.phase = .error(msg)
            HapticService.error()
        }
    }
}

enum VoiceSettings {
    static var defaultMode: AIMode {
        get {
            if let raw = UserDefaults.standard.string(forKey: "nocoai.voiceMode"),
               let mode = AIMode(rawValue: raw) {
                return mode
            }
            return .flash
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "nocoai.voiceMode")
        }
    }
}
