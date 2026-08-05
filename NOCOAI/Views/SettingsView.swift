import AVFoundation
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme
    @State private var voiceMode: AIMode = VoiceSettings.defaultMode
    @State private var autoSpeak = true
    @State private var voiceId = ""
    @State private var voices: [AVSpeechSynthesisVoice] = []
    @State private var previewSynth = AVSpeechSynthesizer()
    @State private var nameDraft = ""

    var body: some View {
        NavigationStack {
            List {
                Section("NOCO Sync") {
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
                        HapticService.modeChange()
                    }

                    Toggle("Spoken Reply", isOn: $autoSpeak)
                        .onChange(of: autoSpeak) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "nocoai.autoSpeak")
                            HapticService.toggle()
                        }

                    Picker("Stimme", selection: $voiceId) {
                        Text("Automatisch (beste)").tag("")
                        ForEach(voices, id: \.identifier) { voice in
                            Text(voiceLabel(voice)).tag(voice.identifier)
                        }
                    }
                    .onChange(of: voiceId) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "nocoai.voiceId")
                        previewVoice(identifier: newValue)
                    }
                } header: {
                    Text("Speak")
                } footer: {
                    Text("Antworten sollen schneller kommen — Sprechtempo bleibt normal.")
                }

                Section {
                    TextField("Dein Name", text: $nameDraft)
                        .textInputAutocapitalization(.words)
                        .onSubmit {
                            connection.profile.setName(nameDraft)
                            HapticService.selection()
                        }

                    Picker("Persönlichkeit", selection: Binding(
                        get: { connection.profile.profile.personality },
                        set: {
                            connection.profile.setPersonality($0)
                            HapticService.modeChange()
                        }
                    )) {
                        ForEach(NocoPersonality.allCases) { p in
                            Text("\(p.label) — \(p.subtitle)").tag(p)
                        }
                    }

                    ForEach(connection.profile.profile.facts, id: \.self) { fact in
                        HStack {
                            Text(fact)
                            Spacer()
                            Button(role: .destructive) {
                                connection.profile.removeFact(fact)
                                HapticService.soft()
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }

                    HStack {
                        TextField("Fakt / Erinnerung…", text: Binding(
                            get: { connection.profile.draftFact },
                            set: { connection.profile.draftFact = $0 }
                        ))
                        Button("Hinzufügen") {
                            connection.profile.addFact(connection.profile.draftFact)
                            HapticService.success()
                        }
                        .disabled(connection.profile.draftFact.trimmingCharacters(in: .whitespacesAndNewlines).count < 4)
                    }

                    if connection.isOnline {
                        Button {
                            Task {
                                await connection.profile.pullRemote()
                                nameDraft = connection.profile.profile.userName
                                HapticService.success()
                            }
                        } label: {
                            Label(
                                connection.profile.isSyncing ? "Sync…" : "Vom PC laden",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                        }
                        .disabled(connection.profile.isSyncing)
                    }
                } header: {
                    Text("Dein Profil")
                } footer: {
                    Text("Name, Persönlichkeit und Fakten gehen unsichtbar an die KI — bei Think & Intelligent. Nicht bei Blitz, Wissen oder Speak.")
                }

                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("NOCO AI Tastatur")
                                .font(.body.weight(.semibold))
                            Text(CompanionCredentials.isConfigured
                                  ? "PC-Verbindung bereit für die Tastatur"
                                  : "Zuerst mit dem PC koppeln")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "keyboard")
                            .foregroundStyle(NOCOAITheme.accent)
                    }

                    Text("""
                    1. Einstellungen → Allgemein → Tastatur → Tastaturen → Tastatur hinzufügen → NOCO AI
                    2. Tippe auf „NOCO AI“ → Vollzugriff erlauben (nötig für die KI)
                    3. In jeder App: Globus-Taste halten → NOCO AI wählen
                    4. Nach dem Koppeln unten „Zugangsdaten aktualisieren“ tippen
                    5. Text tippen oder markieren → Aktion oben tippen (Verbessern, Kürzer, NOCO …)
                    """)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    Button {
                        HapticService.open()
                        CompanionCredentials.sync(
                            host: connection.serverHost,
                            port: connection.serverPort,
                            token: KeychainService.load(account: "nocoai.token"),
                            deviceName: connection.deviceName
                        )
                        HapticService.success()
                    } label: {
                        Label("Zugangsdaten für Tastatur aktualisieren", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!connection.isPaired)
                } header: {
                    Text("KI-Tastatur")
                } footer: {
                    Text("Vollzugriff erlaubt Netzwerk zum PC. Ohne Vollzugriff funktioniert die KI-Leiste nicht. SideStore muss die App Group „group.de.noco.nocoai“ sowohl für die App als auch für die Tastatur behalten. Nach dem Koppeln „Zugangsdaten aktualisieren“ tippen.")
                }

                Section("Erweitert") {
                    NavigationLink {
                        CodeStudioView()
                            .environmentObject(connection)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Code Assist")
                                Text("Optional — läuft auf dem PC")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                        }
                    }
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

                Section("Kurzbefehl Speak") {
                    Text("Kurzbefehle-App → „Mit NOCO sprechen“ zum Home-Bildschirm hinzufügen. Die App startet Speak im Hintergrund (Live Activity); das Speak-Fenster öffnet sich nicht.")
                        .font(.footnote)
                    Text("Link: nocoai://speak · Stoppen: „NOCO Sprachmodus beenden“")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button("Speak jetzt testen") {
                        HapticService.medium()
                        connection.launchSpeakFromShortcut()
                    }
                }

                Section("Info") {
                    Text("NOCO AI Companion v5.3")
                    Text("Vision · Bild-Edit · Tastatur · Speak")
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
                nameDraft = connection.profile.profile.userName
                Task {
                    await connection.profile.pullRemote()
                    nameDraft = connection.profile.profile.userName
                }
            }
            .onDisappear {
                connection.profile.setName(nameDraft)
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

    private func previewVoice(identifier: String) {
        previewSynth.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: "Hallo, ich bin NOCO AI. So klingt diese Stimme.")
        if identifier.isEmpty {
            utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        } else {
            utterance.voice = AVSpeechSynthesisVoice(identifier: identifier)
                ?? AVSpeechSynthesisVoice(language: "de-DE")
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { /* best effort */ }
        HapticService.selection()
        previewSynth.speak(utterance)
    }
}
