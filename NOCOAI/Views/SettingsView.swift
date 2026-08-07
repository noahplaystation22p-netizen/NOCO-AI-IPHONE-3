import AVFoundation
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme
    @State private var autoSpeak = true
    @State private var speakFullAccess = false
    @State private var liveKnowledge: LiveKnowledgePolicy = .auto
    @State private var speakLiveKnowledge: LiveKnowledgePolicy = .auto
    @State private var voiceId = NOCOSpeakVoiceID.natural
    @State private var voiceStyle: NOCOSpeakVoiceStyle = .natural
    @State private var speakRate: Double = 1.0
    @State private var speakPitch: Double = 1.0
    @State private var voices: [AVSpeechSynthesisVoice] = []
    @State private var previewSynth = AVSpeechSynthesizer()
    @State private var nameDraft = ""
    /// Skip auto-preview when Settings first loads / binds the saved voice.
    @State private var voicePreviewArmed = false

    var body: some View {
            List {
                Section("NOCO Sync") {
                    LabeledContent("PC-Adresse", value: connection.serverHost)
                    LabeledContent("Port", value: String(connection.serverPort))
                    LabeledContent("API", value: connection.baseURLString)
                    LabeledContent("Status", value: connection.isOnline ? "Online" : "Offline")
                    LabeledContent("Pfad", value: connection.activePath.label)
                    if !connection.localHost.isEmpty {
                        LabeledContent("Lokal", value: connection.localHost)
                    }
                    if !connection.remoteHost.isEmpty {
                        LabeledContent("Remote", value: connection.remoteHost)
                    }
                }

                Section {
                    Toggle("Automatisch Tailscale", isOn: Binding(
                        get: { connection.autoUseRemote },
                        set: { connection.setAutoUseRemote($0) }
                    ))
                    Toggle("Zuhause zurück zu WLAN", isOn: Binding(
                        get: { connection.autoSwitchToLocal },
                        set: { connection.setAutoSwitchToLocal($0) }
                    ))
                    if !connection.remoteHost.isEmpty {
                        Button("Jetzt über Tailscale verbinden") {
                            Task { await connection.confirmRemoteConnection() }
                        }
                    }
                } header: {
                    Text("Remote (Tailscale)")
                } footer: {
                    Text("Einfach: PC „Remote starten“, iPhone Tailscale VPN an. Die App wechselt automatisch, wenn WLAN fehlt. Zuhause wechselt sie zurück.")
                }

                Section {
                    Picker("Live Knowledge", selection: $liveKnowledge) {
                        ForEach(LiveKnowledgePolicy.allCases) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                    .onChange(of: liveKnowledge) { _, newValue in
                        LiveKnowledgePolicy.current = newValue
                        HapticService.toggle()
                    }
                    Text(liveKnowledge.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("NOCO Live Knowledge")
                } footer: {
                    Text("Lokal zuerst. Web nur bei aktuellen Fakten — oder manuell über + → Internet.")
                }

                Section {
                    Picker("Internetzugriff", selection: $speakLiveKnowledge) {
                        ForEach(LiveKnowledgePolicy.allCases) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                    .onChange(of: speakLiveKnowledge) { _, newValue in
                        SpeakLiveKnowledgePolicy.current = newValue
                        HapticService.toggle()
                    }
                    Text(speakLiveKnowledge.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Antworten vorlesen", isOn: $autoSpeak)
                        .onChange(of: autoSpeak) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "nocoai.autoSpeak")
                            HapticService.toggle()
                        }

                    Toggle("NOCO Vollzugriff", isOn: $speakFullAccess)
                        .onChange(of: speakFullAccess) { _, newValue in
                            SpeakFullAccess.isEnabled = newValue
                            HapticService.toggle()
                        }

                    Picker("Stimme", selection: $voiceId) {
                        Text("NOCO Natural Voice").tag(NOCOSpeakVoiceID.natural)
                        Text("Automatisch (beste)").tag(NOCOSpeakVoiceID.automatic)
                        ForEach(Array(voices.enumerated()), id: \.element.identifier) { index, voice in
                            Text(voiceLabel(voice, index: index)).tag(voice.identifier)
                        }
                    }
                    .onChange(of: voiceId) { _, newValue in
                        NOCOSpeakVoiceSettings.voiceIdentifier = newValue
                        connection.speak.voice.preferredVoiceIdentifier = newValue
                        guard voicePreviewArmed else { return }
                        previewVoice(identifier: newValue)
                    }

                    Picker("Sprachstil", selection: $voiceStyle) {
                        ForEach(NOCOSpeakVoiceStyle.allCases) { style in
                            Text("\(style.label) — \(style.subtitle)").tag(style)
                        }
                    }
                    .onChange(of: voiceStyle) { _, newValue in
                        NOCOSpeakVoiceSettings.style = newValue
                        HapticService.selection()
                        guard voicePreviewArmed else { return }
                        previewVoice(identifier: voiceId)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Sprechgeschwindigkeit")
                            Spacer()
                            Text(rateLabel)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $speakRate, in: 0.7...1.2, step: 0.05)
                            .onChange(of: speakRate) { _, newValue in
                                NOCOSpeakVoiceSettings.rateMultiplier = Float(newValue)
                            }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Tonhöhe")
                            Spacer()
                            Text(pitchLabel)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $speakPitch, in: 0.85...1.2, step: 0.05)
                            .onChange(of: speakPitch) { _, newValue in
                                NOCOSpeakVoiceSettings.pitchMultiplier = Float(newValue)
                            }
                    }

                    Button {
                        previewVoice(identifier: voiceId)
                    } label: {
                        Label("Stimme anhören", systemImage: "speaker.wave.2.fill")
                    }
                } header: {
                    Text("NOCO Voice AI")
                } footer: {
                    Text(speakFooter)
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
                    Text("Name, Persönlichkeit und Fakten gehen unsichtbar an die KI — bei Think & Intelligent. Nicht bei Blitz, Wissen oder Voice AI.")
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
                                  ? "Bereit"
                                  : "Zuerst PC koppeln")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Circle()
                            .fill(CompanionCredentials.isConfigured ? NOCOAITheme.success : Color.orange)
                            .frame(width: 8, height: 8)
                    }

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
                    }
                    .disabled(!connection.isPaired)

                    NavigationLink {
                        KeyboardCustomizationView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Tastatur anpassen")
                                Text("Chips · Shortcuts · Fragen")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }

                    DisclosureGroup("Setup-Hilfe") {
                        VStack(alignment: .leading, spacing: 8) {
                            keyboardSetupStep(1, "App mit PC koppeln")
                            keyboardSetupStep(2, "Zugangsdaten aktualisieren")
                            keyboardSetupStep(3, "iPhone → Tastatur → NOCO AI")
                            keyboardSetupStep(4, "Vollzugriff erlauben")
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("KI-Tastatur")
                } footer: {
                    Text("Doppel-Leertaste = Punkt. Entf halten = schneller löschen. Chip „Fragen“ = Mini-Chat.")
                }

                Section("Erweitert") {
                    NavigationLink {
                        CodeStudioView()
                            .environmentObject(connection)
                    } label: {
                        Label("Code Assist", systemImage: "chevron.left.forwardslash.chevron.right")
                    }

                    TextField("Gerätename", text: $connection.deviceName)

                    Button("Status aktualisieren") {
                        Task { await connection.refreshStatus(showLoading: true) }
                    }
                    Button("Verbindung trennen", role: .destructive) {
                        connection.disconnect()
                        HapticService.medium()
                    }
                }

                DisclosureGroup {
                    Text("Kurzbefehl „NOCO Voice AI“ auf den Action Button legen. Start: Island + Zuhören (ohne Speak-Screen). Erneut: sofort beenden. Link: nocoai://speak")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Voice AI jetzt testen") {
                        HapticService.medium()
                        connection.toggleVoiceAIFromShortcut()
                    }
                } label: {
                    Text("Voice-AI-Kurzbefehl")
                }

                Section("Info") {
                    Text(appVersionLabel)
                    Text("Chat · Voice AI · Agent · Live Screen · Bilder")
                        .font(.footnote)
                        .foregroundStyle(NOCOAITheme.secondaryText(for: scheme))
                }
            }
            .navigationTitle("Einstellungen")
            .onAppear {
                voicePreviewArmed = false
                NOCOSpeakVoiceSettings.ensureDefaults()
                VoiceSettings.defaultMode = .flash
                if UserDefaults.standard.object(forKey: "nocoai.autoSpeak") == nil {
                    autoSpeak = true
                } else {
                    autoSpeak = UserDefaults.standard.bool(forKey: "nocoai.autoSpeak")
                }
                voiceId = NOCOSpeakVoiceSettings.voiceIdentifier
                voiceStyle = NOCOSpeakVoiceSettings.style
                speakRate = Double(NOCOSpeakVoiceSettings.rateMultiplier)
                speakPitch = Double(NOCOSpeakVoiceSettings.pitchMultiplier)
                speakFullAccess = SpeakFullAccess.isEnabled
                liveKnowledge = LiveKnowledgePolicy.current
                speakLiveKnowledge = SpeakLiveKnowledgePolicy.current
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

    private var appVersionLabel: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "7.9"
        return "NOCO AI · v\(short)"
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

    private var speakFooter: String {
        var parts: [String] = []
        parts.append("Internetzugriff: \(speakLiveKnowledge.title) — bei aktuellen Fragen sagt NOCO „Ich schaue kurz nach.“ und nutzt Live Knowledge.")
        if voiceId == NOCOSpeakVoiceID.natural {
            parts.append("NOCO Natural Voice: beste Premium-/Neural-Stimme auf dem Gerät + natürlichere Prosodie — ohne Cloud-Latenz.")
        }
        parts.append(
            speakFullAccess
                ? "Vollzugriff: Tools starten automatisch aus der Sprache."
                : "Sicherheitsmodus: Vor Tools fragt NOCO kurz nach."
        )
        return parts.joined(separator: " ")
    }

    private var rateLabel: String {
        let pct = Int((speakRate * 100).rounded())
        return "\(pct)%"
    }

    private var pitchLabel: String {
        String(format: "%.2f", speakPitch)
    }

    private func voiceLabel(_ voice: AVSpeechSynthesisVoice, index: Int) -> String {
        let q: String
        switch voice.quality {
        case .premium: q = "Premium"
        case .enhanced: q = "Enhanced"
        default: q = "Standard"
        }
        return "Voice \(index + 1) · \(voice.name) · \(q)"
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
        let sample = "Hallo, ich bin NOCO. So klingt diese Stimme im Sprachmodus."
        let natural = identifier == NOCOSpeakVoiceID.natural
            || (identifier.isEmpty && NOCOSpeakVoiceSettings.usesNaturalPipeline)
        let text = natural ? VoiceService.naturalizeForSpeech(sample) : sample
        let utterance = AVSpeechUtterance(string: text)

        if identifier == NOCOSpeakVoiceID.natural || identifier.isEmpty {
            let ranked = voices.sorted { a, b in
                qualityRank(a) > qualityRank(b)
            }
            utterance.voice = ranked.first ?? AVSpeechSynthesisVoice(language: "de-DE")
        } else {
            utterance.voice = AVSpeechSynthesisVoice(identifier: identifier)
                ?? AVSpeechSynthesisVoice(language: "de-DE")
        }
        utterance.rate = NOCOSpeakVoiceSettings.resolvedRate(naturalBase: natural)
        utterance.pitchMultiplier = NOCOSpeakVoiceSettings.resolvedPitch(naturalBase: natural)
        utterance.volume = 1.0
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { /* best effort */ }
        HapticService.selection()
        previewSynth.speak(utterance)
    }
}
