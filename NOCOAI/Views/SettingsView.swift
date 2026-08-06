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
    /// Skip auto-preview when Settings first loads / binds the saved voice.
    @State private var voicePreviewArmed = false

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
                        guard voicePreviewArmed else { return }
                        previewVoice(identifier: newValue)
                    }

                    Button {
                        previewVoice(identifier: voiceId)
                    } label: {
                        Label("Stimme anhören", systemImage: "speaker.wave.2.fill")
                    }
                } header: {
                    Text("Speak")
                } footer: {
                    Text("Antworten sollen schneller kommen — Sprechtempo bleibt normal. Vorschau nur bei Stimmenwechsel oder „Anhören“.")
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
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.34, green: 0.56, blue: 1.0),
                                            Color(red: 0.42, green: 0.78, blue: 0.95)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 44, height: 44)
                            Image(systemName: "keyboard.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("NOCO AI Tastatur")
                                .font(.body.weight(.semibold))
                            Text(CompanionCredentials.isConfigured
                                  ? "Bereit — PC-Verbindung freigegeben"
                                  : "Noch nicht bereit — zuerst PC koppeln")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Circle()
                            .fill(CompanionCredentials.isConfigured ? NOCOAITheme.success : Color.orange)
                            .frame(width: 8, height: 8)
                    }
                    .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 10) {
                        keyboardSetupStep(1, "App mit dem PC koppeln (online)")
                        keyboardSetupStep(2, "Zugangsdaten unten aktualisieren")
                        keyboardSetupStep(3, "iPhone → Tastatur → NOCO AI hinzufügen")
                        keyboardSetupStep(4, "Vollzugriff erlauben")
                        keyboardSetupStep(5, "Text markieren → KI-Chip tippen")
                    }
                    .padding(.vertical, 4)

                    Button {
                        HapticService.open()
                        CompanionCredentials.sync(
                            host: connection.serverHost,
                            port: connection.serverPort,
                            token: KeychainService.load(account: "nocoai.token"),
                            deviceName: connection.deviceName
                        )
                        KeyboardChipPreferences.pushToKeyboard()
                        HapticService.success()
                    } label: {
                        Label("Zugangsdaten aktualisieren", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(NOCOAITheme.accent)
                    .disabled(!connection.isPaired)

                    NavigationLink {
                        KeyboardCustomizationView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Tastatur anpassen")
                                    .font(.body.weight(.semibold))
                                Text("Chips sortieren · eigene KI-Shortcuts mit Prompt")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(NOCOAITheme.accent)
                        }
                    }
                } header: {
                    Text("KI-Tastatur")
                } footer: {
                    Text("App Group group.de.noco.nocoai in SideStore aktiv lassen. Ohne Vollzugriff kein Netzwerk. Nach Anpassen kurz Globus tippen, damit Chips neu laden.")
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
                    Text("NOCO AI Companion v6.2")
                    Text("Premium keyboard · custom AI shortcuts")
                        .font(.footnote)
                        .foregroundStyle(NOCOAITheme.secondaryText(for: scheme))
                }
            }
            .navigationTitle("Einstellungen")
            .onAppear {
                voicePreviewArmed = false
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
                    // Arm after bind so opening Settings never speaks
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    await MainActor.run { voicePreviewArmed = true }
                }
            }
            .onDisappear {
                previewSynth.stopSpeaking(at: .immediate)
                connection.profile.setName(nameDraft)
            }
        }
    }

    private func keyboardSetupStep(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(NOCOAITheme.accent.opacity(0.9)))
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
