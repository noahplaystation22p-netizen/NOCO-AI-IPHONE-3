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
            IntelligenceAtmosphere()
            FloatingIntelligenceDots(count: 20)
                .opacity(0.55)

            VStack(spacing: 18) {
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
                        Text(connection.isOnline ? "PC live" : "Offline")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(connection.isOnline ? NOCOAITheme.success : NOCOAITheme.danger)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                VStack(spacing: 4) {
                    Text("NOCO Voice")
                        .font(.title2.weight(.bold))
                    Text("Modell: \(VoiceSettings.defaultMode.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VoiceRainbowOrb(phase: voice.phase, level: voice.level)

                Text(displayText)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 28)
                    .frame(minHeight: 58)
                    .animation(.easeOut(duration: 0.2), value: displayText)

                Text(statusLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let err = connection.chat.lastError, case .error = voice.phase {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(NOCOAITheme.danger)
                        .padding(.horizontal)
                }

                Spacer()

                holdButton
                    .padding(.bottom, 36)
            }
        }
        .task {
            let ok = await voice.requestPermissions()
            if !ok {
                statusLine = "Mikrofon & Spracherkennung in den iPhone-Einstellungen erlauben"
            } else if !connection.isOnline {
                statusLine = "PC offline — erst in NOCO AI X Companion starten"
            }
        }
    }

    private var displayText: String {
        switch voice.phase {
        case .listening:
            return voice.liveTranscript.isEmpty ? "Ich höre zu…" : voice.liveTranscript
        case .processing:
            return voice.liveTranscript.isEmpty ? "Sende an PC…" : voice.liveTranscript
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
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(red: 0.35, green: 0.8, blue: 1),
                                Color(red: 0.6, green: 0.4, blue: 1),
                                Color(red: 1.0, green: 0.4, blue: 0.7),
                                Color(red: 0.35, green: 0.8, blue: 1)
                            ],
                            center: .center
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 96, height: 96)
                    .opacity(isHolding ? 1 : 0.45)
                    .scaleEffect(isHolding ? 1.08 : 1)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.35, green: 0.75, blue: 1),
                                Color(red: 0.55, green: 0.4, blue: 1),
                                Color(red: 0.95, green: 0.4, blue: 0.75)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 84, height: 84)
                    .shadow(color: Color(red: 0.5, green: 0.4, blue: 1).opacity(0.55), radius: 24)
                    .overlay(
                        Image(systemName: isHolding ? "waveform" : "mic.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                    )
            }
            .scaleEffect(isHolding ? 1.1 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isHolding)
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
        case .processing: return "PC denkt (\(VoiceSettings.defaultMode.label))…"
        case .speaking: return "Sprachausgabe…"
        default:
            return connection.isOnline ? "Gedrückt halten" : "Keine Verbindung"
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
            statusLine = "Zuhören…"
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

        statusLine = "Sende an NOCO AI X…"
        voice.phase = .processing
        HapticService.send()

        let reply = await connection.chat.sendAndReturnReply(text, modeOverride: VoiceSettings.defaultMode)

        if let reply, !reply.isEmpty {
            lastReply = reply
            if voice.autoSpeakReplies {
                statusLine = "Sprachausgabe…"
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
