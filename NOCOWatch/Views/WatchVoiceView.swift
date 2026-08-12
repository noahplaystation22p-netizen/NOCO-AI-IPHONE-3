import SwiftUI

struct WatchVoiceView: View {
    @EnvironmentObject private var controller: WatchController

    private var voice: WatchVoiceEngine { controller.voice }
    private var phase: WatchStatusSnapshot.Phase { voice.phase }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                WatchIntelligenceCore(phase: phase, diameter: 96, level: voice.audioLevel)

                Text(statusLabel)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .animation(.easeInOut(duration: 0.25), value: phase)

                if voice.isActive, phase == .listening || phase == .idle {
                    TextField("Diktieren oder tippen…", text: Binding(
                        get: { voice.draft },
                        set: { voice.draft = $0 }
                    ))
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.send)
                    .onSubmit {
                        Task { await voice.submitDraft() }
                    }

                    Button {
                        Task { await voice.submitDraft() }
                    } label: {
                        Label("Senden", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WatchRainbow.teal)
                    .disabled(voice.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !voice.transcript.isEmpty, phase != .speaking {
                    Text(voice.transcript)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if phase == .speaking, !voice.spokenText.isEmpty {
                    Text(voice.spokenText)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }

                if voice.isActive {
                    Button("Stop") {
                        controller.stopVoice()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    Button {
                        Task { await controller.startVoice() }
                    } label: {
                        Label("Voice AI", systemImage: "mic.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WatchRainbow.teal)
                }

                Text("Flash · Diktat über Tastatur-Mic")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 6)
        }
    }

    private var statusLabel: String {
        switch phase {
        case .idle: return voice.isActive ? "Ready" : "Voice AI"
        case .listening: return "Listening…"
        case .thinking, .connecting: return "Thinking…"
        case .speaking: return "NOCO is speaking"
        case .error: return "Nicht erreichbar"
        }
    }
}
