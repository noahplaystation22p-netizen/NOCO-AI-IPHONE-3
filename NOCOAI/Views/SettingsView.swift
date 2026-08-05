import AVFoundation
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme
    @State private var voiceMode: AIMode = VoiceSettings.defaultMode
    @State private var autoSpeak = true
    @State private var voiceId = ""
    @State private var voices: [AVSpeechSynthesisVoice] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Intelligence Sync") {
                    LabeledContent("PC-Adresse", value: connection.serverHost)
                    LabeledContent("Port", value: String(connection.serverPort))
                    LabeledContent("API", value: connection.baseURLString)
                    LabeledContent("Status", value: connection.isOnline ? "Online" : "Offline")
                }

                Section {
                    Picker("Speak-Modell", selection: $voiceMode) {
                        ForEach(AIMode.allCases) { mode in
                            Text("\(mode.label) — \(mode.subtitle)").tag(mode)
                        }
                    }
                    .onChange(of: voiceMode) { _, newValue in
                        VoiceSettings.defaultMode = newValue
                        HapticService.selection()
                    }

                    Toggle("Spoken Reply", isOn: $autoSpeak)
                        .onChange(of: autoSpeak) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "nocoai.autoSpeak")
                        }

                    Picker("Stimme", selection: $voiceId) {
                        Text("Automatisch (beste)").tag("")
                        ForEach(voices, id: \.identifier) { voice in
                            Text(voiceLabel(voice)).tag(voice.identifier)
                        }
                    }
                    .onChange(of: voiceId) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "nocoai.voiceId")
                    }
                } header: {
                    Text("Speak")
                } footer: {
                    Text("Standard ist Blitz für schnelle Spoken Replies. Stimme bevorzugt Premium/Enhanced Deutsch.")
                }

                Section("Gerät") {
                    TextField("Gerätename", text: $connection.deviceName)
                }

                Section {
                    Button("Status aktualisieren") {
                        Task { await connection.refreshStatus(showLoading: true) }
                    }
                    Button("Verbindung trennen", role: .destructive) {
                        connection.disconnect()
                        HapticService.medium()
                    }
                }

                Section("Info") {
                    Text("NOCO AI Companion v3.0")
                    Text("Speak · Schreibwerkzeuge · Bildideen · Intelligence Sync")
                        .font(.footnote)
                        .foregroundStyle(NOCOAITheme.secondaryText(for: scheme))
                }
            }
            .navigationTitle("Einstellungen")
            .onAppear {
                voiceMode = VoiceSettings.defaultMode
                if UserDefaults.standard.object(forKey: "nocoai.autoSpeak") == nil {
                    autoSpeak = true
                } else {
                    autoSpeak = UserDefaults.standard.bool(forKey: "nocoai.autoSpeak")
                }
                voiceId = UserDefaults.standard.string(forKey: "nocoai.voiceId") ?? ""
                voices = AVSpeechSynthesisVoice.speechVoices()
                    .filter { $0.language.hasPrefix("de") }
                    .sorted { qualityRank($0) > qualityRank($1) }
            }
        }
    }

    private func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        let q: String
        switch voice.quality {
        case .premium: q = "Premium"
        case .enhanced: q = "Enhanced"
        default: q = "Standard"
        }
        return "\(voice.name) · \(q)"
    }

    private func qualityRank(_ voice: AVSpeechSynthesisVoice) -> Int {
        switch voice.quality {
        case .premium: return 3
        case .enhanced: return 2
        default: return 1
        }
    }
}
