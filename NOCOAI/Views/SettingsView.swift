import AVFoundation
import SwiftUI
import UIKit

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
    @State private var voiceLogStatus = ""
    /// Skip auto-preview when Settings first loads / binds the saved voice.
    @State private var voicePreviewArmed = false
    @State private var thinkStatus: ThinkModelStatusResponse?
    @State private var thinkLoading = false
    @State private var thinkInstalling = false
    @State private var thinkError = ""

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
                    HStack(spacing: 10) {
                        pathButton(
                            title: "Lokal",
                            subtitle: connection.localHost.isEmpty ? "WLAN" : connection.localHost,
                            selected: connection.activePath == .local,
                            enabled: !connection.localHost.isEmpty || connection.activePath == .local
                        ) {
                            Task { await connection.confirmLocalConnection() }
                        }
                        pathButton(
                            title: "Remote",
                            subtitle: connection.remoteHost.isEmpty ? "Tailscale" : connection.remoteHost,
                            selected: connection.activePath == .remote,
                            enabled: !connection.remoteHost.isEmpty
                        ) {
                            Task { await connection.confirmRemoteConnection() }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))

                    Toggle("Automatisch Remote", isOn: Binding(
                        get: { connection.autoUseRemote },
                        set: { connection.setAutoUseRemote($0) }
                    ))
                    Toggle("Zuhause zurück zu WLAN", isOn: Binding(
                        get: { connection.autoSwitchToLocal },
                        set: { connection.setAutoSwitchToLocal($0) }
                    ))
                } header: {
                    Text("Verbindung")
                } footer: {
                    Text("QR koppelt immer über WLAN. Später: hier oder automatisch auf Remote (Tailscale) wechseln — ohne neuen QR. PC: „Remote starten“, iPhone: Tailscale VPN an.")
                }

                Section {
                    NavigationLink {
                        ConnectionDiagnoseView()
                            .environmentObject(connection)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Diagnose")
                                Text("Local · Tailscale · TCP · HTTP · Log")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "stethoscope")
                        }
                    }
                } header: {
                    Text("Verbindung · Diagnose")
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
                        Text("Natural AI Voice").tag(NOCOSpeakVoiceID.natural)
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

                Section {
                    if let think = thinkStatus {
                        LabeledContent("Status") {
                            Text(think.isReady ? "Bereit" : "Nicht installiert")
                                .foregroundStyle(think.isReady ? NOCOAITheme.success : Color.orange)
                        }
                        if let model = think.thinkModel, !model.isEmpty {
                            LabeledContent("Installiert", value: model)
                        }
                        if let rec = think.recommendedThink, !rec.isEmpty {
                            LabeledContent("Empfohlen", value: rec)
                        }
                        if let flash = think.flashModel, !flash.isEmpty {
                            LabeledContent("Flash", value: flash)
                        }
                        if let hw = think.hardware {
                            if let ram = hw.totalRamGb {
                                LabeledContent("RAM", value: String(format: "%.0f GB", ram))
                            }
                            if let vram = hw.vramMiB, vram > 0 {
                                LabeledContent("VRAM", value: "\(vram) MiB")
                            }
                            if let reason = hw.thinkReason, !reason.isEmpty {
                                Text(reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let msg = think.message, !msg.isEmpty {
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if thinkLoading {
                        ProgressView("Status laden…")
                    } else if !thinkError.isEmpty {
                        Text(thinkError)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("PC verbinden, um Think-Status zu sehen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        Task { await refreshThinkStatus() }
                    } label: {
                        Label("Status aktualisieren", systemImage: "arrow.clockwise")
                    }
                    .disabled(!connection.isOnline || thinkInstalling)

                    if !(thinkStatus?.isReady ?? false) {
                        Button {
                            Task { await installThinkModel() }
                        } label: {
                            if thinkInstalling {
                                Label("Installiere Think… (kann dauern)", systemImage: "arrow.down.circle")
                            } else {
                                Label("Think einrichten", systemImage: "brain.head.profile")
                            }
                        }
                        .disabled(!connection.isOnline || thinkInstalling || thinkLoading)
                    }
                } header: {
                    Text("Think-Modell")
                } footer: {
                    Text("FLASH bleibt das schnelle Modell. THINK ist stärker und wird nur bei komplexen Aufgaben oder manueller Auswahl geladen. Voice AI und Bilder bleiben getrennt.")
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
                    Button {
                        UIPasteboard.general.string = VoiceDebugLog.exportText()
                        voiceLogStatus = "Voice Logs kopiert"
                        HapticService.success()
                    } label: {
                        Label("Voice Logs kopieren", systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive) {
                        VoiceDebugLog.clear()
                        voiceLogStatus = "Voice Logs gelöscht"
                        HapticService.soft()
                    } label: {
                        Label("Voice Logs löschen", systemImage: "trash")
                    }
                    if !voiceLogStatus.isEmpty {
                        Text(voiceLogStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                    await refreshThinkStatus()
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

    private func refreshThinkStatus() async {
        guard connection.isOnline, let api = connection.companionAPI() else {
            thinkError = connection.isOnline ? "API nicht bereit" : "Offline"
            return
        }
        thinkLoading = true
        thinkError = ""
        defer { thinkLoading = false }
        do {
            thinkStatus = try await api.fetchThinkModelStatus()
        } catch {
            thinkError = error.localizedDescription
        }
    }

    private func installThinkModel() async {
        guard connection.isOnline, let api = connection.companionAPI() else {
            thinkError = "PC offline — Think kann nicht installiert werden"
            return
        }
        thinkInstalling = true
        thinkError = ""
        defer { thinkInstalling = false }
        do {
            let resp = try await api.installThinkModel()
            if let think = resp.think {
                thinkStatus = think
            } else {
                await refreshThinkStatus()
            }
            if resp.ok != true {
                thinkError = resp.error ?? "Installation fehlgeschlagen"
                HapticService.soft()
            } else {
                HapticService.success()
            }
        } catch {
            thinkError = error.localizedDescription
            HapticService.soft()
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
            parts.append("Natural AI Voice: beste Premium-/Neural-Stimme auf dem Gerät, variable Prosodie und Gesprächsstil — ohne Cloud-Latenz und ohne schwere PC-TTS.")
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

    private func pathButton(
        title: String,
        subtitle: String,
        selected: Bool,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        selected
                            ? LinearGradient(
                                colors: [NOCORainbow.blue, NOCORainbow.violet],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color.primary.opacity(0.06), Color.primary.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                    )
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
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
        let natural = identifier == NOCOSpeakVoiceID.natural
            || (identifier.isEmpty && NOCOSpeakVoiceSettings.usesNaturalPipeline)
        let sample = natural
            ? "Ja — sieht gut aus. Morgen wird's voraussichtlich sonnig. So klingt Natural AI Voice."
            : "Hallo, ich bin NOCO. So klingt diese Stimme im Sprachmodus."
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
        let prosody = NOCOSpeakVoiceSettings.chunkProsody(
            text: text,
            index: 0,
            total: 1,
            naturalBase: natural
        )
        utterance.rate = prosody.rate
        utterance.pitchMultiplier = prosody.pitch
        utterance.preUtteranceDelay = prosody.prePause
        utterance.postUtteranceDelay = prosody.postPause
        utterance.volume = 1.0
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { /* best effort */ }
        HapticService.selection()
        previewSynth.speak(utterance)
    }
}
