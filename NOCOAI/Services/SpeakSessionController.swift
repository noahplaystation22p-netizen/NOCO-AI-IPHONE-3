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
    /// Rich assistant phase for Island + Speak UI (beyond mic phase).
    @Published var assistantPhase: SpeakAssistantPhase = .idle
    /// Safety-mode pending tool confirmation.
    @Published var pendingToolConfirm: SpeakIntent?
    private var pendingToolOriginal: String?
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
            assistantPhase = .listening
            statusLine = liveOk
                ? "Rede natürlich — NOCO versteht Absichten"
                : (SpeakLiveActivityManager.areActivitiesEnabled
                    ? "Zuhören aktiv · Live Activity prüfen (Einstellungen → NOCO AI)"
                    : "Zuhören aktiv · Live Activities in iOS-Einstellungen aktivieren")
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
        pendingToolConfirm = nil
        pendingToolOriginal = nil
        assistantPhase = .idle
        connection?.liveScreen.suppressAutoVision = false
        voice.setMuted(false)
        endBackgroundKeepAlive()
        SpeakLiveActivityManager.end()
        // Only tear down Speak-owned vision Island — never kill Image gen / Agent / Eraser.
        ImageLiveActivityManager.end(immediate: true, onlyIfOwner: .speakVision)
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
            assistantPhase = pendingToolConfirm == nil ? .listening : .awaitingConfirm
            statusLine = pendingToolConfirm?.confirmationQuestion ?? "Wieder Zuhören…"
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

        // Resolve safety-mode confirmation first.
        if let pending = pendingToolConfirm {
            if SpeakIntentEngine.isAffirmation(text) {
                pendingToolConfirm = nil
                let original = pendingToolOriginal ?? text
                pendingToolOriginal = nil
                await executeIntent(pending, originalText: original, connection: connection)
                return
            }
            if SpeakIntentEngine.isDenial(text) {
                pendingToolConfirm = nil
                pendingToolOriginal = nil
                await speakBrief("Alles klar — ich starte nichts.", connection: connection)
                return
            }
            // New request replaces pending confirm.
            pendingToolConfirm = nil
            pendingToolOriginal = nil
        }

        let intent = SpeakIntentEngine.classify(
            text,
            cameraOn: visionCameraEnabled,
            screenShareOn: screenShareEnabled,
            hasPendingFrame: pendingVisionJPEG != nil,
            lastAssistantHadImage: connection.chat.messages.reversed().contains {
                $0.role == .assistant && ($0.localImageData != nil || $0.imageURL != nil)
            }
        )

        if case .endSpeak = intent.action {
            exitSpeakToChat()
            return
        }

        // Safety mode: ask before tools.
        if intent.needsToolAccess, !SpeakFullAccess.isEnabled {
            pendingToolConfirm = intent
            pendingToolOriginal = text
            assistantPhase = .awaitingConfirm
            statusLine = intent.confirmationQuestion
            voice.phase = .processing
            pushLiveActivity(force: true)
            await speakBrief(intent.confirmationQuestion, connection: connection)
            return
        }

        await executeIntent(intent, originalText: text, connection: connection)
    }

    private func executeIntent(
        _ intent: SpeakIntent,
        originalText: String,
        connection: ConnectionStore
    ) async {
        isBusy = true
        mapAssistantPhase(for: intent)
        statusLine = intent.statusLine
        voice.phase = .processing
        pushLiveActivity(force: true)
        HapticService.send()
        guard isRunning else {
            isBusy = false
            return
        }

        switch intent.action {
        case .endSpeak:
            isBusy = false
            exitSpeakToChat()
            return

        case .screenMemory:
            await handleScreenMemory(connection: connection)
            return

        case .createImage(let prompt):
            await handleImageCreate(prompt: prompt, ack: intent.spokenAck, connection: connection)
            return

        case .runAgent(let goal):
            await handleAgent(goal: goal, ack: intent.spokenAck, connection: connection)
            return

        case .magicEraser:
            await handleMagicEraser(ack: intent.spokenAck, connection: connection)
            return

        case .summarize:
            await handleSummarize(originalText: originalText, style: intent.style, connection: connection)
            return

        case .visionAnalyze:
            await handleVision(originalText: originalText, connection: connection)
            return

        case .conversation(let depth):
            await handleConversation(
                originalText: originalText,
                depth: depth,
                style: intent.style,
                useLiveKnowledge: intent.useLiveKnowledge,
                ack: intent.spokenAck,
                connection: connection
            )
            return
        }
    }

    private func mapAssistantPhase(for intent: SpeakIntent) {
        switch intent.action {
        case .createImage: assistantPhase = .creatingImage
        case .runAgent: assistantPhase = .agentWorking
        case .visionAnalyze: assistantPhase = .vision
        case .magicEraser: assistantPhase = .thinking
        case .conversation where intent.useLiveKnowledge: assistantPhase = .webSearch
        case .summarize, .conversation, .screenMemory: assistantPhase = .thinking
        case .endSpeak: assistantPhase = .idle
        }
    }

    private func handleScreenMemory(connection: ConnectionStore) async {
        let memory = connection.liveScreen.sessionSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let briefing = connection.liveScreen.contextBriefing.trimmingCharacters(in: .whitespacesAndNewlines)
        let recall = !memory.isEmpty ? memory : briefing
        if !recall.isEmpty {
            let reply = "Vorhin auf dem Bildschirm:\n\n\(recall)"
            await finishWithReply(reply, connection: connection)
        } else {
            await handleConversation(
                originalText: "Was war zuletzt auf dem Bildschirm?",
                depth: .flash,
                style: SpeakStyleHints(),
                useLiveKnowledge: false,
                ack: "",
                connection: connection
            )
        }
    }

    private func handleImageCreate(prompt: String, ack: String, connection: ConnectionStore) async {
        assistantPhase = .creatingImage
        statusLine = SpeakActivityPhase.creatingImage.title
        pushLiveActivity(force: true)
        if !ack.isEmpty {
            await speakFillerPhrase(ack)
            assistantPhase = .creatingImage
            statusLine = SpeakActivityPhase.creatingImage.title
            pushLiveActivity(force: true)
        }
        guard isRunning else { isBusy = false; return }

        connection.chat.setMode(.image)
        let reply = await connection.chat.sendAndReturnReply(prompt, modeOverride: .image, speak: false)
        let spoken = reply?.trimmingCharacters(in: .whitespacesAndNewlines)
        let final = (spoken?.isEmpty == false)
            ? spoken!
            : "Das Bild ist fertig — du findest es im Chat."
        await finishWithReply(final, connection: connection)
    }

    private func handleAgent(goal: String, ack: String, connection: ConnectionStore) async {
        assistantPhase = .agentWorking
        statusLine = SpeakActivityPhase.agentWorking.title
        pushLiveActivity(force: true)
        if !ack.isEmpty {
            await speakFillerPhrase(ack)
            assistantPhase = .agentWorking
            statusLine = SpeakActivityPhase.agentWorking.title
            pushLiveActivity(force: true)
        }
        guard isRunning else { isBusy = false; return }

        connection.chat.setMode(.agent)
        let reply = await connection.chat.sendAndReturnReply(goal, modeOverride: .agent, speak: false)
        let spoken: String
        if let reply, !reply.isEmpty {
            spoken = String(reply.prefix(900))
        } else {
            spoken = "Die Aufgabe läuft im Chat weiter. Schau dort kurz nach."
        }
        await finishWithReply(spoken, connection: connection)
    }

    private func handleMagicEraser(ack: String, connection: ConnectionStore) async {
        assistantPhase = .thinking
        statusLine = "🪄 Öffne Magischen Radierer…"
        pushLiveActivity(force: true)
        connection.pendingOpenEraser = true
        connection.pendingTab = 1
        showSpeakUI = false
        await finishWithReply(ack.isEmpty ? "Ich öffne den Magischen Radierer." : ack, connection: connection)
    }

    private func handleSummarize(originalText: String, style: SpeakStyleHints, connection: ConnectionStore) async {
        assistantPhase = .thinking
        let prompt = """
        [NOCO SPEAK · ZUSAMMENFASSUNG]
        Erstelle eine klare, gesprochene Zusammenfassung auf Deutsch.
        \(style.shorter ? "Besonders knapp." : "Präzise, aber gut hörbar.")
        Auftrag: \(originalText)
        """
        let reply = await connection.chat.sendAndReturnReply(
            prompt,
            modeOverride: style.prefersDepth ? .think : .writing,
            speak: true
        )
        await finishWithReply(reply ?? "", connection: connection, allowRetry: originalText)
    }

    private func handleVision(originalText: String, connection: ConnectionStore) async {
        assistantPhase = .vision
        connection.liveScreen.suppressAutoVision = true
        statusLine = "👁 Ich schaue mir das an…"
        pushLiveActivity(force: true)
        try? await Task.sleep(nanoseconds: 180_000_000)

        var jpeg = pendingVisionJPEG
        pendingVisionJPEG = nil
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

        guard let jpeg else {
            let tip = visionCameraEnabled || screenShareEnabled
                ? "Ich brauche noch ein klares Bild — tippe kurz auf Momentaufnahme."
                : "Aktiviere die Kamera oder den Bildschirm, dann frag nochmal."
            await finishWithReply(tip, connection: connection)
            return
        }

        statusLine = screenShareEnabled ? "👁 Analysiere Bildschirm…" : "👁 Analysiere Bild…"
        ImageLiveActivityManager.start(
            prompt: screenShareEnabled ? "Live Screen · Speak" : "Vision · Speak",
            owner: .speakVision
        )
        ImageLiveActivityManager.update(
            progress: 0.35,
            status: "Analysiere…",
            insight: String(originalText.prefix(60)),
            etaSeconds: 8,
            phase: .rendering,
            force: true
        )

        var prompt = originalText
        let briefing = connection.liveScreen.contextBriefing
        if screenShareEnabled, !briefing.isEmpty {
            prompt = """
            \(originalText)

            [Live-Screen-Kontext]
            \(briefing)
            """
        }
        let reply = await connection.chat.sendVisionForSpeak(jpeg: jpeg, userText: prompt)
        ImageLiveActivityManager.complete(prompt: "Vision fertig")
        await finishWithReply(reply ?? "", connection: connection, allowRetry: originalText)
    }

    private func handleConversation(
        originalText: String,
        depth: AIMode,
        style: SpeakStyleHints,
        useLiveKnowledge: Bool,
        ack: String,
        connection: ConnectionStore
    ) async {
        if useLiveKnowledge {
            connection.chat.armLiveKnowledge(.web)
            assistantPhase = .webSearch
            statusLine = SpeakActivityPhase.webSearch.title
            pushLiveActivity(force: true)
            let filler = ack.isEmpty ? SpeakIntentEngine.randomWebAck() : ack
            await speakFillerPhrase(filler)
            guard isRunning else { isBusy = false; return }
            assistantPhase = .webSearch
            statusLine = SpeakActivityPhase.webSearch.title
            pushLiveActivity(force: true)
        } else {
            assistantPhase = .thinking
            statusLine = SpeakActivityPhase.thinking.title
            pushLiveActivity(force: true)
            if !ack.isEmpty {
                await speakFillerPhrase(ack)
                guard isRunning else { isBusy = false; return }
                assistantPhase = .thinking
                statusLine = SpeakActivityPhase.thinking.title
                pushLiveActivity(force: true)
            }
        }
        let prompt = VoiceService.speakPrompt(originalText, depth: depth, style: style)
        let reply = await connection.chat.sendAndReturnReply(
            prompt,
            modeOverride: depth,
            speak: true
        )
        await finishWithReply(reply ?? "", connection: connection, allowRetry: originalText)
    }

    private func finishWithReply(
        _ reply: String,
        connection: ConnectionStore,
        allowRetry: String? = nil
    ) async {
        guard isRunning else {
            isBusy = false
            return
        }

        var resolved = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolved.isEmpty, let allowRetry {
            consecutiveFailures += 1
            statusLine = "Verbindung wird wiederhergestellt…"
            assistantPhase = .thinking
            voice.phase = .processing
            pushLiveActivity(force: true)
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard isRunning else { isBusy = false; return }
            let prompt = VoiceService.speakPrompt(allowRetry, depth: .flash, style: SpeakStyleHints())
            resolved = (await connection.chat.sendAndReturnReply(prompt, modeOverride: .flash, speak: true) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if resolved.isEmpty {
                let msg = Self.friendlySpeakError(connection.chat.lastError ?? "")
                statusLine = msg
                assistantPhase = .error
                voice.phase = .error(msg)
                pushLiveActivity(force: true)
                if voice.autoSpeakReplies, consecutiveFailures <= 2 {
                    isBusy = false
                    assistantPhase = .speaking
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
        if !resolved.isEmpty {
            lastReply = resolved
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard isRunning else { isBusy = false; return }
            if voice.autoSpeakReplies {
                statusLine = SpeakActivityPhase.speaking.title
                assistantPhase = .speaking
                pushLiveActivity(force: true)
                resumeTask?.cancel()
                isBusy = false
                connection.liveScreen.suppressAutoVision = true
                voice.speak(resolved)
                startSpeakWatchdog()
            } else {
                connection.liveScreen.suppressAutoVision = false
                connection.liveScreen.resumeQueuedAnalysisIfNeeded()
                voice.phase = .idle
                assistantPhase = .listening
                isBusy = false
                scheduleResumeListening(after: 0.05)
                await drainPendingUtterance()
            }
        } else {
            isBusy = false
            assistantPhase = .listening
            scheduleResumeListening(after: 0.2)
            await drainPendingUtterance()
        }
    }

    /// Short spoken bridge while work continues — does not resume the mic.
    private func speakFillerPhrase(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, voice.autoSpeakReplies else { return }
        resumeTask?.cancel()
        assistantPhase = .speaking
        lastReply = trimmed
        statusLine = trimmed
        pushLiveActivity(force: true)
        voice.speak(trimmed)
        for _ in 0..<160 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard isRunning else {
                voice.stopSpeaking(notifyFinished: false)
                return
            }
            if case .speaking = voice.phase { continue }
            break
        }
        // Keep busy; do not startSpeakWatchdog — caller continues the task.
        try? await Task.sleep(nanoseconds: 60_000_000)
    }

    /// End-of-turn spoken line that resumes listening afterward.
    private func speakBrief(_ text: String, connection: ConnectionStore) async {
        resumeTask?.cancel()
        assistantPhase = .speaking
        lastReply = text
        statusLine = text
        pushLiveActivity(force: true)
        if voice.autoSpeakReplies {
            isBusy = false
            voice.speak(text)
            startSpeakWatchdog()
        } else {
            isBusy = false
            scheduleResumeListening(after: 0.2)
            await drainPendingUtterance()
        }
    }

    // Legacy path removed — intent engine owns routing.

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
            return "Verbindung wird wiederhergestellt… Sprich einfach weiter, wenn du bereit bist."
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

    func pushLiveActivity(force: Bool) {
        guard isRunning else { return }
        if !SpeakLiveActivityManager.isActive {
            SpeakLiveActivityManager.start()
        }

        // Prefer rich assistant phase while tools / thinking / web are active.
        let phase: SpeakActivityPhase
        switch assistantPhase {
        case .creatingImage, .agentWorking, .vision, .awaitingConfirm, .thinking, .webSearch:
            phase = assistantPhase.activityPhase
        default:
            switch voice.phase {
            case .listening: phase = .listening
            case .processing:
                if assistantPhase == .webSearch {
                    phase = .webSearch
                } else {
                    phase = assistantPhase == .thinking ? .thinking : .processing
                }
            case .speaking: phase = .speaking
            case .error: phase = .error
            case .idle: phase = isMuted ? .idle : (assistantPhase == .listening ? .listening : .idle)
            }
        }

        let detail: String
        if isMuted {
            switch voice.phase {
            case .speaking: detail = lastReply.isEmpty ? "Stumm · Wiedergabe…" : lastReply
            default: detail = "Mic stumm — Mute aus zum Sprechen"
            }
        } else if pendingToolConfirm != nil {
            detail = pendingToolConfirm?.confirmationQuestion ?? "Bestätigung nötig"
        } else {
            switch phase {
            case .listening:
                detail = voice.liveTranscript.isEmpty ? "Rede natürlich…" : voice.liveTranscript
            case .speaking:
                detail = lastReply
            case .thinking, .processing:
                detail = statusLine.isEmpty ? SpeakActivityPhase.thinking.title : statusLine
            case .webSearch:
                detail = statusLine.isEmpty ? "Live Knowledge · Quellen werden gelesen…" : statusLine
            case .creatingImage:
                detail = "Bildmodell arbeitet…"
            case .agentWorking:
                detail = "Plant, recherchiert und führt aus…"
            case .vision:
                detail = "Vision versteht die Szene…"
            case .awaitingConfirm:
                detail = "Ja oder Nein sagen"
            case .error:
                if case .error(let m) = voice.phase { detail = m } else { detail = statusLine }
            case .idle:
                detail = SpeakFullAccess.isEnabled ? "Vollzugriff · Assistent bereit" : "Bereit"
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
            force: force,
            titleOverride: phase.title
        )
    }
}
