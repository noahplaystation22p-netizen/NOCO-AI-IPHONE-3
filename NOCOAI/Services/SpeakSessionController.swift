import Foundation
import SwiftUI
import UIKit
import Combine

/// App-scoped Speak session so audio + Live Activity survive leaving the Speak UI.
@MainActor
final class SpeakSessionController: ObservableObject {
    let voice = VoiceService()

    @Published var isRunning = false
    @Published var lastReply = ""
    @Published var statusLine = "Speak bereit"
    @Published var showSpeakUI = false
    @Published var isMuted = false
    /// Camera preview may be on; Vision only runs on explicit snapshot / vision utterance.
    @Published var visionCameraEnabled = false
    /// Live Screen frames available for vision questions (no continuous upload).
    @Published var screenShareEnabled = false
    /// One-shot JPEG waiting to be analyzed with the next relevant utterance.
    @Published var pendingVisionJPEG: Data?
    var visionFrameProvider: (() -> UIImage?)?

    private weak var connection: ConnectionStore?
    private var isBusy = false
    private var wired = false
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private var resumeTask: Task<Void, Never>?
    /// One queued utterance while NOCO is processing / speaking.
    private var pendingUtterance: String?
    private var consecutiveFailures = 0
    private var cancellables = Set<AnyCancellable>()

    /// Live Screen / vision gate — true while Speak is busy or TTS is playing.
    var isBusyForVision: Bool {
        if isBusy { return true }
        if case .speaking = voice.phase { return true }
        if case .processing = voice.phase { return true }
        return false
    }

    func bind(connection: ConnectionStore) {
        self.connection = connection
        guard !wired else { return }
        wired = true
        voice.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        voice.onAutoUtterance = { [weak self] text in
            Task { @MainActor in
                await self?.enqueueUtterance(text)
            }
        }
        voice.onSpeakFinished = { [weak self] in
            guard let self else { return }
            self.connection?.liveScreen.suppressAutoVision = false
            self.connection?.liveScreen.resumeQueuedAnalysisIfNeeded()
            self.scheduleResumeListening(after: 0.08)
            // Process anything queued while we were speaking.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                await self.drainPendingUtterance()
            }
            self.objectWillChange.send()
        }
    }

    func openUI() {
        showSpeakUI = true
    }

    func start() {
        guard let connection, connection.isOnline else {
            statusLine = "PC offline — erst verbinden"
            return
        }
        Task { @MainActor in
            await startAsync(connection: connection)
        }
    }

    private func startAsync(connection: ConnectionStore) async {
        // 1) Live Activity FIRST — Lock Screen banner + Dynamic Island
        let liveOk = await SpeakLiveActivityManager.startAndWait()
        do {
            try voice.activateBackgroundAudioSession()
            isRunning = true
            isBusy = false
            isMuted = false
            voice.setMuted(false)
            voice.sessionActive = true
            beginBackgroundKeepAlive()
            try voice.startListening(autoEnd: true)
            HapticService.speakCue()
            statusLine = liveOk
                ? "Zuhören — Pause sendet an NOCO"
                : "Zuhören aktiv · Live Activity prüfen (Einstellungen → NOCO AI)"
            pushLiveActivity(force: true)
            // Second ensure — some devices need a follow-up update
            try? await Task.sleep(nanoseconds: 200_000_000)
            if isRunning {
                if !SpeakLiveActivityManager.isActive {
                    _ = await SpeakLiveActivityManager.startAndWait()
                }
                pushLiveActivity(force: true)
            }
        } catch {
            isRunning = false
            endBackgroundKeepAlive()
            voice.phase = .error(error.localizedDescription)
            statusLine = "Mikrofon-Fehler"
            SpeakLiveActivityManager.end()
        }
    }

    func stop(playCue: Bool = true) {
        if playCue { HapticService.speakCue() }
        resumeTask?.cancel()
        resumeTask = nil
        // Mute first so nothing else is captured/sent, then tear down
        isMuted = true
        voice.setMuted(true)
        voice.sessionActive = false
        voice.stopSpeaking(notifyFinished: false)
        voice.stopListening(cancel: true)
        isRunning = false
        isMuted = false
        visionCameraEnabled = false
        screenShareEnabled = false
        visionFrameProvider = nil
        pendingVisionJPEG = nil
        connection?.liveScreen.suppressAutoVision = false
        voice.setMuted(false)
        endBackgroundKeepAlive()
        SpeakLiveActivityManager.end()
        ImageLiveActivityManager.end(immediate: true)
        voice.phase = .idle
        statusLine = "Speak gestoppt"
    }

    /// Full exit: stop mic/TTS, camera, Live Screen — return to Chat.
    /// Only for active Speak sessions (voice commands).
    func exitSpeakToChat() {
        guard let connection else {
            stop(playCue: true)
            showSpeakUI = false
            return
        }
        statusLine = "Sprachmodus beendet"
        HapticService.speakCue()

        // Stop any in-flight vision / live analysis noise
        connection.liveScreen.suppressAutoVision = true
        if connection.liveScreen.isActive || screenShareEnabled {
            connection.liveScreen.stopSession(offerSave: false, keepContext: true)
        }
        screenShareEnabled = false
        visionCameraEnabled = false
        visionFrameProvider = nil
        pendingVisionJPEG = nil

        stop(playCue: false)
        showSpeakUI = false
        // Tab 0 = Chat
        connection.pendingTab = 0
    }

    func toggleMute() {
        setMuted(!isMuted)
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        voice.setMuted(muted)
        if muted {
            resumeTask?.cancel()
            statusLine = "Stumm — Antwort wird vorgelesen, Mic aus"
            pushLiveActivity(force: true)
            HapticService.soft()
        } else if isRunning {
            statusLine = "Mic an — sprich, kurze Pause sendet"
            scheduleResumeListening(after: 0.2)
            HapticService.medium()
        }
    }

    private func beginBackgroundKeepAlive() {
        endBackgroundKeepAlive()
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "NOCO Speak") { [weak self] in
            Task { @MainActor in
                self?.endBackgroundKeepAlive()
            }
        }
    }

    private func endBackgroundKeepAlive() {
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }

    func ensureBackgroundPresence() {
        guard isRunning else { return }
        try? voice.activateBackgroundAudioSession()
        beginBackgroundKeepAlive()
        if !SpeakLiveActivityManager.isActive {
            SpeakLiveActivityManager.start()
        }
        pushLiveActivity(force: true)
        statusLine = isMuted
            ? "Stumm · Live Activity aktiv"
            : "Speak läuft · Sperrbildschirm / Island"
    }

    /// Reliable re-listen after TTS (debounce + settle delay).
    private func scheduleResumeListening(after delay: TimeInterval) {
        resumeTask?.cancel()
        resumeTask = Task { [weak self] in
            let ns = UInt64(max(0, delay) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.resumeListening()
            }
        }
    }

    /// Poll until TTS leaves speaking, then resume mic.
    private func startSpeakWatchdog() {
        resumeTask?.cancel()
        resumeTask = Task { [weak self] in
            for _ in 0..<400 {
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard let self, !Task.isCancelled else { return }
                let speaking = await MainActor.run {
                    if case .speaking = self.voice.phase { return true }
                    return false
                }
                if !speaking { break }
            }
            try? await Task.sleep(nanoseconds: 40_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.connection?.liveScreen.suppressAutoVision = false
                self?.connection?.liveScreen.resumeQueuedAnalysisIfNeeded()
                self?.resumeListening()
            }
        }
    }

    private func resumeListening() {
        guard isRunning, connection?.isOnline == true else { return }
        guard !isMuted else {
            statusLine = "Stumm — tippe Mute aus zum Sprechen"
            voice.phase = .idle
            pushLiveActivity(force: true)
            return
        }
        guard !isBusy else {
            scheduleResumeListening(after: 0.12)
            return
        }
        if case .speaking = voice.phase {
            scheduleResumeListening(after: 0.08)
            return
        }
        do {
            try voice.activateListeningAfterTTS()
            try voice.startListening(autoEnd: true)
            statusLine = "Wieder Zuhören…"
            pushLiveActivity(force: true)
            Task { await drainPendingUtterance() }
        } catch {
            statusLine = "Zuhören unterbrochen — nochmal…"
            scheduleResumeListening(after: 0.25)
        }
    }

    private func enqueueUtterance(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Only gate on real work — VoiceService sets .processing before callback,
        // which previously parked every utterance forever in pendingUtterance.
        if isBusy {
            pendingUtterance = trimmed
            statusLine = "Einen Moment…"
            return
        }
        if case .speaking = voice.phase {
            pendingUtterance = trimmed
            return
        }
        await handleUtterance(trimmed)
        if let next = pendingUtterance {
            pendingUtterance = nil
            await handleUtterance(next)
        }
    }

    private func handleUtterance(_ text: String) async {
        guard isRunning, !isBusy, let connection else {
            if isBusy {
                pendingUtterance = text
            }
            return
        }
        guard !isMuted else { return }

        // Voice command: end speak without sending to the PC (only while Speak is active)
        if Self.isEndSpeakCommand(text) {
            exitSpeakToChat()
            return
        }

        isBusy = true

        statusLine = "Verarbeite…"
        voice.phase = .processing
        pushLiveActivity(force: true)
        HapticService.send()
        guard isRunning else {
            isBusy = false
            return
        }

        // Answer from Live Screen memory without a new frame upload
        if Self.asksForScreenMemory(text) {
            let memory = connection.liveScreen.sessionSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            let briefing = connection.liveScreen.contextBriefing.trimmingCharacters(in: .whitespacesAndNewlines)
            let recall = !memory.isEmpty ? memory : briefing
            if !recall.isEmpty {
                let reply = """
                Vorhin auf dem Bildschirm (aus dem Live-Screen-Kontext):

                \(recall)
                """
                lastReply = reply
                try? await Task.sleep(nanoseconds: 220_000_000)
                guard isRunning else {
                    isBusy = false
                    return
                }
                consecutiveFailures = 0
                if voice.autoSpeakReplies {
                    connection.liveScreen.suppressAutoVision = true
                    statusLine = "Spoken Reply…"
                    isBusy = false
                    voice.speak(reply)
                    startSpeakWatchdog()
                } else {
                    voice.phase = .idle
                    isBusy = false
                    scheduleResumeListening(after: 0.05)
                    await drainPendingUtterance()
                }
                return
            }
        }

        var reply: String?
        let wantsVision = (visionCameraEnabled || screenShareEnabled) && (
            pendingVisionJPEG != nil
                || screenShareEnabled
                || Self.asksForVision(text)
        )
        if wantsVision {
            // Freeze Live Screen auto-uploads for this whole vision turn (incl. TTS).
            connection.liveScreen.suppressAutoVision = true
            statusLine = "Ich schaue mir das kurz an…"
            pushLiveActivity(force: true)
            try? await Task.sleep(nanoseconds: 220_000_000)

            var jpeg = pendingVisionJPEG
            pendingVisionJPEG = nil
            // Prefer live preview when screen share is on (latestJPEG can go stale).
            if jpeg == nil, screenShareEnabled,
               let preview = connection.liveScreen.latestPreview,
               let data = preview.jpegData(compressionQuality: 0.78) {
                jpeg = data
            }
            if jpeg == nil, screenShareEnabled, let screenJPEG = connection.liveScreen.latestJPEG {
                jpeg = screenJPEG
            }
            if jpeg == nil, let image = visionFrameProvider?() {
                jpeg = image.jpegData(compressionQuality: 0.78)
            }

            if let jpeg {
                statusLine = screenShareEnabled
                    ? "Ich analysiere den Bildschirm…"
                    : "Ich analysiere das Bild…"
                ImageLiveActivityManager.start(prompt: screenShareEnabled ? "Live Screen · Speak" : "Vision · Speak")
                ImageLiveActivityManager.update(
                    progress: 0.35,
                    status: "Analysiere…",
                    insight: String(text.prefix(60)),
                    etaSeconds: 8,
                    phase: .rendering,
                    force: true
                )

                var prompt = text
                let briefing = connection.liveScreen.contextBriefing
                if screenShareEnabled, !briefing.isEmpty {
                    prompt = """
                    \(text)

                    [Live-Screen-Kontext]
                    \(briefing)
                    """
                }
                reply = await connection.chat.sendVisionForSpeak(jpeg: jpeg, userText: prompt)
                ImageLiveActivityManager.complete(prompt: "Vision fertig")
            } else {
                statusLine = screenShareEnabled
                    ? "Kein Bildschirmbild — Übertragung starten"
                    : "Kein Kamerabild"
                let prompt = VoiceService.voiceOnlyPrompt(text)
                reply = await connection.chat.sendAndReturnReply(
                    prompt,
                    modeOverride: .flash,
                    speak: true
                )
            }
        } else {
            // Speak always uses Flash — fast spoken replies, never Think/Auto.
            let prompt = VoiceService.voiceOnlyPrompt(text)
            statusLine = "Verarbeite…"
            reply = await connection.chat.sendAndReturnReply(
                prompt,
                modeOverride: .flash,
                speak: true
            )
        }

        guard isRunning else {
            isBusy = false
            return
        }

        // One automatic retry on empty / transport failures — never invent a chatty fallback.
        if reply == nil || reply?.isEmpty == true {
            consecutiveFailures += 1
            let raw = connection.chat.lastError ?? ""
            statusLine = "Ich hatte kurz ein Problem mit der Verbindung. Ich versuche es erneut."
            voice.phase = .processing
            pushLiveActivity(force: true)
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard isRunning else {
                isBusy = false
                return
            }
            let prompt = VoiceService.voiceOnlyPrompt(text)
            reply = await connection.chat.sendAndReturnReply(
                prompt,
                modeOverride: .flash,
                speak: true
            )
            if reply == nil || reply?.isEmpty == true {
                let msg = Self.friendlySpeakError(raw.isEmpty ? (connection.chat.lastError ?? "") : raw)
                statusLine = msg
                voice.phase = .error(msg)
                pushLiveActivity(force: true)
                if voice.autoSpeakReplies, consecutiveFailures <= 2 {
                    isBusy = false
                    voice.speak(msg)
                    startSpeakWatchdog()
                } else {
                    isBusy = false
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    if isRunning { scheduleResumeListening(after: 0.2) }
                    await drainPendingUtterance()
                }
                return
            }
        }

        consecutiveFailures = 0
        if let reply, !reply.isEmpty {
            lastReply = reply
            // Short natural beat before TTS
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard isRunning else {
                isBusy = false
                return
            }
            if voice.autoSpeakReplies {
                statusLine = "Spoken Reply…"
                pushLiveActivity(force: true)
                resumeTask?.cancel()
                isBusy = false
                connection.liveScreen.suppressAutoVision = true
                voice.speak(reply)
                startSpeakWatchdog()
            } else {
                connection.liveScreen.suppressAutoVision = false
                connection.liveScreen.resumeQueuedAnalysisIfNeeded()
                voice.phase = .idle
                isBusy = false
                scheduleResumeListening(after: 0.05)
                await drainPendingUtterance()
            }
        } else {
            isBusy = false
            scheduleResumeListening(after: 0.2)
            await drainPendingUtterance()
        }
    }

    private func drainPendingUtterance() async {
        guard let next = pendingUtterance, isRunning, !isBusy else { return }
        pendingUtterance = nil
        await handleUtterance(next)
    }

    private static func friendlySpeakError(_ raw: String) -> String {
        let low = raw.lowercased()
        if low.contains("offline") || low.contains("unreachable") || low.contains("nicht erreichbar")
            || low.contains("timed out") || low.contains("timeout") || low.contains("network")
            || low.contains("verbindung") || low.contains("host is down") || low.contains("error 64") {
            return "Ich hatte kurz ein Problem mit der Verbindung. Ich versuche es erneut, wenn du weitersprichst."
        }
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Die Antwort ist nicht angekommen. Bitte wiederhole kurz, was du gesagt hast."
        }
        return "Kurz gestört — ich bin wieder bereit. Sag es gerne noch einmal."
    }

    /// Capture one still for the next vision-aware utterance (no continuous upload).
    func captureVisionSnapshot() {
        if screenShareEnabled {
            if let preview = connection?.liveScreen.latestPreview,
               let jpeg = preview.jpegData(compressionQuality: 0.8) {
                pendingVisionJPEG = jpeg
                statusLine = "Bildschirm-Moment bereit"
                HapticService.imageSnap()
                return
            }
            if let jpeg = connection?.liveScreen.latestJPEG {
                pendingVisionJPEG = jpeg
                statusLine = "Bildschirm-Moment bereit"
                HapticService.imageSnap()
                return
            }
        }
        guard let image = visionFrameProvider?(),
              let jpeg = image.jpegData(compressionQuality: 0.8) else {
            statusLine = "Kein Bild — Kamera oder Bildschirm prüfen"
            HapticService.error()
            return
        }
        pendingVisionJPEG = jpeg
        statusLine = "Momentaufnahme bereit"
        HapticService.imageSnap()
    }

    /// Enable Live Screen context inside Speak (Broadcast / existing session).
    func enableScreenShare() async {
        guard let connection else { return }
        let live = connection.liveScreen
        if !live.hasConsent {
            statusLine = "Live Screen Zustimmung nötig — öffne Studio → Live Screen"
            HapticService.error()
            connection.pendingOpenLiveScreen = true
            connection.pendingTab = 2
            return
        }
        do {
            if !live.isActive {
                try live.startSession()
            }
            // Speak-driven: don't auto-spam vision; only on questions / snapshots
            live.autoAssistEnabled = false
            screenShareEnabled = true
            statusLine = "🖥 Bildschirm — tippe rot „Übertragen“ falls noch nicht aktiv"
            HapticService.success()
        } catch {
            statusLine = (error as? LocalizedError)?.errorDescription ?? "Live Screen Start fehlgeschlagen"
            HapticService.error()
        }
    }

    func disableScreenShare() {
        screenShareEnabled = false
        if let live = connection?.liveScreen, live.isActive {
            // Keep session if user opened Live Screen UI separately; only clear Speak flag
            live.autoAssistEnabled = true
            live.suppressAutoVision = false
        }
        statusLine = isRunning ? "Bildschirm aus · nur Sprache" : "Speak bereit"
        HapticService.soft()
    }

    private static func asksForVision(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.range(
            of: #"\b(was ist das|was siehst|was soll ich|wo tippe|wo klicke|schau|schau mal|erkenne|beschreib|analysiere.*(bild|foto|das|bildschirm)|sieh dir|sieh mal|kamera|bildschirm|screen|fenster|fehlermeldung)\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func asksForScreenMemory(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.range(
            of: #"\b(was war|nochmal.*(bildschirm|screen)|vorher.*(bildschirm|fenster)|erinnerst du|was stand|was war auf)\b"#,
            options: .regularExpression
        ) != nil
    }

    /// „Sprachmodus beenden“ — only evaluated inside an active Speak session (`handleUtterance`).
    private static func isEndSpeakCommand(_ text: String) -> Bool {
        let n = text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "de_DE"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = n
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Ignore meta questions about the words themselves
        if compact.contains("bedeutet") || compact.contains("heisst") || compact.contains("heißt")
            || compact.contains("was ist ein") || compact.contains("erkläre") || compact.contains("erklaere") {
            return false
        }
        // Commands are short — long sentences are normal chat
        if compact.count > 64 { return false }

        let phrases = [
            "sprachmodus beenden",
            "beende sprachmodus",
            "beenden sprachmodus",
            "stoppe sprachmodus",
            "stopp sprachmodus",
            "stop sprachmodus",
            "ende sprachmodus",
            "sprachmodus ende",
            "sprachmodus stoppen",
            "zurück zum chat",
            "zurueck zum chat",
            "zurück in den chat",
            "zurueck in den chat",
            "back to chat",
            "end language mode",
            "end speak",
            "stop speak",
            "stoppe speak",
            "speak beenden",
            "speak stoppen",
            "noco speak stoppen",
            "beende speak",
            "schließ sprachmodus",
            "schliess sprachmodus",
            "exit speak",
            "quit speak"
        ]
        if phrases.contains(where: { compact.contains($0) }) { return true }

        // Exact short stops only (avoid matching normal sentences)
        let exact = ["stopp", "stop", "stopp speak", "stop speak"]
        return exact.contains(compact)
    }

    func pushLiveActivity(force: Bool) {
        guard isRunning else { return }
        if !SpeakLiveActivityManager.isActive {
            SpeakLiveActivityManager.start()
        }
        let phase: SpeakActivityPhase
        switch voice.phase {
        case .listening: phase = .listening
        case .processing: phase = .processing
        case .speaking: phase = .speaking
        case .error: phase = .error
        case .idle: phase = isMuted ? .idle : .idle
        }
        let detail: String
        if isMuted {
            switch voice.phase {
            case .speaking: detail = lastReply.isEmpty ? "Stumm · Wiedergabe…" : lastReply
            default: detail = "Mic stumm — Mute aus zum Sprechen"
            }
        } else {
            switch voice.phase {
            case .listening:
                detail = voice.liveTranscript.isEmpty ? "Sprich weiter…" : voice.liveTranscript
            case .speaking:
                detail = lastReply
            case .processing:
                detail = "Blitz · mit Chat-Kontext"
            case .error(let m):
                detail = m
            case .idle:
                detail = "Bereit"
            }
        }
        let step = max(voice.bands.count / 7, 1)
        var seven: [Double] = []
        for i in stride(from: 0, to: voice.bands.count, by: step) where seven.count < 7 {
            seven.append(Double(voice.bands[i]))
        }
        while seven.count < 7 { seven.append(Double(voice.level)) }
        SpeakLiveActivityManager.update(
            phase: phase,
            detail: detail,
            level: Double(voice.level),
            bars: seven,
            isOnline: connection?.isOnline ?? false,
            isMuted: isMuted,
            force: force
        )
    }
}
