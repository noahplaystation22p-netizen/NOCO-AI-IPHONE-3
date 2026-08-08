import Foundation
import SwiftUI
import UIKit
import Combine

/// App-scoped Speak session so audio + Live Activity survive leaving the Speak UI.
/// Session authority lives here — Dynamic Island is status-only, never the voice engine.
@MainActor
final class SpeakSessionController: ObservableObject {
    let voice = VoiceService()

    /// Hard session state machine (controller-owned). Engine `voice.phase` is subordinate.
    enum SessionPhase: Equatable {
        case idle
        case listening
        case processing
        case speaking
        case recovering
        case exiting
    }

    @Published var isRunning = false
    @Published private(set) var sessionPhase: SessionPhase = .idle
    @Published var lastReply = ""
    @Published var statusLine = "Voice AI bereit"
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
    private var busySince: Date?
    private var activeTurn: UInt64 = 0
    private var wired = false
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private var resumeTask: Task<Void, Never>?
    private var resumeTaskStartedAt: Date?
    /// Bumped on every return-to-listen schedule so stale finishes are ignored.
    private var resumeGeneration: UInt64 = 0
    private var listenHealthTask: Task<Void, Never>?
    private var bgRenewTask: Task<Void, Never>?
    /// One queued utterance while NOCO is processing / speaking.
    private var pendingUtterance: String?
    private var consecutiveFailures = 0
    private var listenRetryCount = 0
    private var cancellables = Set<AnyCancellable>()
    /// While true: never reopen the mic (reply TTS / farewell in progress).
    private var holdMicForTTS = false
    private var holdMicStartedAt: Date?
    /// Set when shutting down Voice AI — skip resume-listening.
    private var isExiting = false

    /// Live Screen / vision gate — true while Speak is busy or TTS is playing.
    var isBusyForVision: Bool {
        if isBusy { return true }
        switch sessionPhase {
        case .processing, .speaking, .exiting: return true
        default: break
        }
        if case .speaking = voice.phase { return true }
        if case .processing = voice.phase { return true }
        return false
    }

    private func beginTurn() -> UInt64 {
        activeTurn &+= 1
        return activeTurn
    }

    private func invalidateTurn() {
        activeTurn &+= 1
    }

    private func turnIsLive(_ turn: UInt64? = nil) -> Bool {
        guard isRunning, !isExiting else { return false }
        if let turn { return turn == activeTurn }
        return true
    }

    private func setBusy(_ on: Bool) {
        isBusy = on
        busySince = on ? Date() : nil
    }

    private func setHoldMicForTTS(_ on: Bool) {
        holdMicForTTS = on
        holdMicStartedAt = on ? Date() : nil
        if on { sessionPhase = .speaking }
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
        voice.onBargeIn = { [weak self] text in
            guard let self else { return }
            // Sync cancel so the TTS watchdog cannot reopen the mic mid-barge-in.
            self.resumeTask?.cancel()
            self.resumeTask = nil
            self.resumeTaskStartedAt = nil
            self.setHoldMicForTTS(false)
            self.setBusy(false)
            self.invalidateTurn()
            self.connection?.chat.cancelSpeakSend()
            Task { @MainActor in
                await self.handleBargeIn(text)
            }
        }
        voice.onSpeakFinished = { [weak self] in
            guard let self else { return }
            if self.isExiting || !self.isRunning {
                self.setHoldMicForTTS(false)
                return
            }
            // TTS finished — always ensure a return-to-listen path is alive.
            // Never leave holdMicForTTS without a live resume task (root cause of "2nd question dies").
            if self.holdMicForTTS || self.sessionPhase == .speaking {
                if self.resumeTask == nil {
                    self.beginReturnToListening(settleSeconds: 0.28)
                }
                VoiceDebugLog.event("TTS_END", "hold→listen")
                self.objectWillChange.send()
                return
            }
            // Keep Live Screen quiet for the whole Speak session — Island is status only.
            self.connection?.liveScreen.suppressAutoVision = true
            VoiceDebugLog.event("TTS_END", "resume")
            self.beginReturnToListening(settleSeconds: 0.22)
        }
    }

    func openUI() {
        showSpeakUI = true
    }

    func start() {
        // Single session — never spawn a second Voice engine.
        if isRunning, !isExiting {
            ensureBackgroundPresence()
            statusLine = "NOCO Voice AI läuft bereits"
            return
        }
        guard let connection, connection.isOnline else {
            statusLine = "PC offline — erst verbinden"
            return
        }
        Task { @MainActor in
            await startAsync(connection: connection)
        }
    }

    private func startAsync(connection: ConnectionStore) async {
        if isRunning, !isExiting {
            ensureBackgroundPresence()
            return
        }
        isExiting = false
        setHoldMicForTTS(false)
        setBusy(false)
        sessionPhase = .recovering
        // Live Activity = status mirror only (not the voice engine).
        let liveOk = await SpeakLiveActivityManager.startAndWait(sessionLabel: "NOCO Voice AI")
        do {
            try voice.activateBackgroundAudioSession()
            isRunning = true
            isMuted = false
            voice.setMuted(false)
            voice.sessionActive = true
            voice.autoSpeakReplies = true
            connection.liveScreen.suppressAutoVision = true
            beginBackgroundKeepAlive()
            startBackgroundRenewLoop()
            startListenHealthLoop()
            try voice.hardReinitAudioForListen()
            try voice.startListening(autoEnd: true)
            HapticService.speakCue()
            sessionPhase = .listening
            assistantPhase = .listening
            VoiceDebugLog.event("VOICE_START", liveOk ? "island=on" : "island=off")
            VoiceDebugLog.event("LISTENING")
            statusLine = liveOk
                ? "NOCO Voice AI aktiviert"
                : (SpeakLiveActivityManager.areActivitiesEnabled
                    ? "Zuhören aktiv · Live Activity prüfen"
                    : "Zuhören aktiv · Live Activities aktivieren")
            VoiceAISessionState.publish(active: true, micOn: true, islandOn: liveOk)
            pushLiveActivity(force: true)
            try? await Task.sleep(nanoseconds: 200_000_000)
            if isRunning {
                if !SpeakLiveActivityManager.isActive {
                    _ = await SpeakLiveActivityManager.startAndWait(sessionLabel: "NOCO Voice AI")
                }
                statusLine = "NOCO Voice AI aktiviert — sprich"
                pushLiveActivity(force: true)
                VoiceAISessionState.publish(active: true, micOn: true, islandOn: SpeakLiveActivityManager.isActive)
            }
        } catch {
            sessionPhase = .idle
            isRunning = false
            listenHealthTask?.cancel()
            listenHealthTask = nil
            bgRenewTask?.cancel()
            bgRenewTask = nil
            endBackgroundKeepAlive()
            voice.phase = .error(error.localizedDescription)
            statusLine = "Mikrofon-Fehler"
            VoiceAISessionState.publish(active: false)
            SpeakLiveActivityManager.end()
        }
    }

    func stop(playCue: Bool = true) {
        if playCue { HapticService.speakCue() }
        isExiting = true
        sessionPhase = .exiting
        setHoldMicForTTS(false)
        invalidateTurn()
        connection?.chat.cancelSpeakSend()
        connection?.liveScreen.suppressAutoVision = false
        resumeTask?.cancel()
        resumeTask = nil
        resumeTaskStartedAt = nil
        listenHealthTask?.cancel()
        listenHealthTask = nil
        bgRenewTask?.cancel()
        bgRenewTask = nil
        // Publish closed state immediately so Shortcuts / Action Button never see a stale "on".
        VoiceAISessionState.publish(active: false, micOn: false, islandOn: false)
        // Mute first so nothing else is captured/sent, then tear down
        isMuted = true
        voice.setMuted(true)
        voice.sessionActive = false
        voice.stopSpeaking(notifyFinished: false)
        voice.stopListening(cancel: true)
        isRunning = false
        setBusy(false)
        isMuted = false
        visionCameraEnabled = false
        screenShareEnabled = false
        visionFrameProvider = nil
        pendingVisionJPEG = nil
        pendingToolConfirm = nil
        pendingToolOriginal = nil
        pendingUtterance = nil
        sessionPhase = .idle
        assistantPhase = .idle
        statusLine = "Voice AI beendet"
        VoiceDebugLog.event("VOICE_EXIT")
        SpeakLiveActivityManager.end()
        ImageLiveActivityManager.end(immediate: true, onlyIfOwner: .speakVision)
        voice.phase = .idle
        endBackgroundKeepAlive()
        showSpeakUI = false
        isExiting = false
        objectWillChange.send()
    }

    /// Stop button / Shortcut / Action Button — instant, silent, no farewell.
    func exitVoiceAISilent() {
        isExiting = true
        setHoldMicForTTS(false)
        invalidateTurn()
        connection?.chat.cancelSpeakSend()
        resumeTask?.cancel()
        voice.stopListening(cancel: true)
        voice.stopSpeaking(notifyFinished: false)
        statusLine = "Voice AI beendet"
        VoiceAISessionState.publish(active: false, micOn: false, islandOn: false)
        SpeakLiveActivityManager.update(
            phase: .idle,
            detail: "Voice AI beendet",
            level: 0.15,
            bars: [0.15, 0.18, 0.2, 0.18, 0.15, 0.12, 0.1],
            isOnline: connection?.isOnline ?? false,
            isMuted: false,
            force: true,
            titleOverride: "Voice AI beendet"
        )

        if let connection {
            connection.liveScreen.suppressAutoVision = true
            if connection.liveScreen.isActive || screenShareEnabled {
                connection.liveScreen.stopSession(offerSave: false, keepContext: true)
            }
        }
        screenShareEnabled = false
        visionCameraEnabled = false
        visionFrameProvider = nil
        pendingVisionJPEG = nil

        stop(playCue: true)
        showSpeakUI = false
        connection?.pendingTab = 0
    }

    /// UI Stop button — silent immediate exit back to Chat.
    func exitSpeakToChat() {
        exitVoiceAISilent()
    }

    /// Spoken farewell exit — only for voice commands like "Voice AI beenden".
    func exitVoiceAIGracefully() async {
        await exitVoiceAI(spokenFarewell: true)
    }

    /// Voice-command exit with polite confirmation.
    func exitVoiceAI(spokenFarewell: Bool) async {
        guard isRunning || showSpeakUI else {
            exitVoiceAISilent()
            return
        }
        if !spokenFarewell {
            exitVoiceAISilent()
            return
        }

        isExiting = true
        setHoldMicForTTS(true)
        resumeTask?.cancel()
        voice.stopListening(cancel: true)
        assistantPhase = .idle
        statusLine = "Voice AI beendet"
        SpeakLiveActivityManager.update(
            phase: .idle,
            detail: "Voice AI beendet",
            level: 0.2,
            bars: [0.2, 0.25, 0.3, 0.25, 0.2, 0.18, 0.15],
            isOnline: connection?.isOnline ?? false,
            isMuted: false,
            force: true,
            titleOverride: "Voice AI beendet"
        )
        // Brief spoken close — no mic reopen afterward.
        if voice.autoSpeakReplies {
            lastReply = "Alles klar, Voice AI beendet."
            voice.speak(lastReply, allowBargeIn: false)
            for _ in 0..<80 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                if case .speaking = voice.phase { continue }
                break
            }
            voice.stopSpeaking(notifyFinished: false)
        }

        if let connection {
            connection.liveScreen.suppressAutoVision = true
            if connection.liveScreen.isActive || screenShareEnabled {
                connection.liveScreen.stopSession(offerSave: false, keepContext: true)
            }
        }
        screenShareEnabled = false
        visionCameraEnabled = false
        visionFrameProvider = nil
        pendingVisionJPEG = nil

        stop(playCue: false)
        showSpeakUI = false
        connection?.pendingTab = 0
        HapticService.speakCue()
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
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "NOCO Voice AI") { [weak self] in
            Task { @MainActor in
                // Renew instead of dying — continuous audio needs a fresh BG task.
                self?.beginBackgroundKeepAlive()
            }
        }
    }

    private func endBackgroundKeepAlive() {
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }

    /// Keep BG task + audio session alive while Island / lock-screen Voice AI runs.
    private func startBackgroundRenewLoop() {
        bgRenewTask?.cancel()
        bgRenewTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard let self, !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.isRunning, !self.isExiting else { return }
                    self.beginBackgroundKeepAlive()
                    try? self.voice.activateBackgroundAudioSession()
                }
            }
        }
    }

    /// If mic dies after TTS in background, reopen without waiting for the user to open the app.
    private func startListenHealthLoop() {
        listenHealthTask?.cancel()
        listenHealthTask = Task { [weak self] in
            while !Task.isCancelled {
                let bg = await MainActor.run { UIApplication.shared.applicationState != .active }
                // Background: poll faster — STT dies silently and UI used to lie about Listening.
                try? await Task.sleep(nanoseconds: bg ? 320_000_000 : 550_000_000)
                guard let self, !Task.isCancelled else { return }
                await MainActor.run {
                    self.ensureListeningHealthy()
                }
            }
        }
    }

    private func ensureListeningHealthy() {
        guard isRunning, !isExiting, !isMuted else { return }

        // Stuck busy without TTS → recover so the next question can send.
        if isBusy, !holdMicForTTS,
           let since = busySince,
           Date().timeIntervalSince(since) > 36 {
            if case .speaking = voice.phase {
                voice.forceFinishIfSpeakingStuck(maxDuration: 120)
                return
            }
            setBusy(false)
            setHoldMicForTTS(false)
            invalidateTurn()
            connection?.chat.cancelSpeakSend()
            statusLine = "NOCO hört wieder zu…"
            sessionPhase = .recovering
            VoiceDebugLog.event("VOICE_RECOVERY", "stuck_busy")
            beginReturnToListening(settleSeconds: 0.08)
            return
        }

        // Speaking hold: force return to listen if TTS ended or watchdog is stuck.
        if holdMicForTTS || sessionPhase == .speaking {
            if case .speaking = voice.phase {
                voice.forceFinishIfSpeakingStuck(maxDuration: 120)
                return
            }
            let holdAge = holdMicStartedAt.map { Date().timeIntervalSince($0) } ?? 99
            let resumeAge = resumeTaskStartedAt.map { Date().timeIntervalSince($0) } ?? 99
            if resumeTask != nil, resumeAge < 2.2, holdAge < 3.5 {
                return
            }
            resumeTask?.cancel()
            resumeTask = nil
            resumeTaskStartedAt = nil
            setHoldMicForTTS(false)
            setBusy(false)
            sessionPhase = .recovering
            statusLine = "NOCO hört wieder zu…"
            VoiceDebugLog.event("VOICE_ERROR", "stuck_hold_forced")
            VoiceDebugLog.event("VOICE_RECOVERY", "health_force_listen")
            beginReturnToListening(settleSeconds: 0.08)
            return
        }

        guard !isBusy else { return }
        if case .speaking = voice.phase { return }
        if case .processing = voice.phase { return }

        let bg = UIApplication.shared.applicationState != .active
        if voice.verifyListeningPipeline() {
            // Keep refreshing STT in background before Apple kills the task.
            voice.refreshRecognitionIfStale(maxAge: bg ? 5 : 18)
            if voice.verifyListeningPipeline() {
                sessionPhase = .listening
                if assistantPhase == .listening || assistantPhase == .idle {
                    assistantPhase = pendingToolConfirm == nil ? .listening : .awaitingConfirm
                }
            }
            return
        }

        // Phase said listening but pipeline is dead — reopen for real.
        sessionPhase = .recovering
        statusLine = "NOCO hört wieder zu…"
        VoiceDebugLog.event("BACKGROUND_RECOVERY", "pipeline_not_active")
        beginReturnToListening(settleSeconds: bg ? 0.12 : 0.05)
    }

    func ensureBackgroundPresence() {
        guard isRunning else { return }
        VoiceDebugLog.event("BACKGROUND_ENTER", "ensure_presence")
        try? voice.activateBackgroundAudioSession()
        beginBackgroundKeepAlive()
        if bgRenewTask == nil { startBackgroundRenewLoop() }
        if listenHealthTask == nil { startListenHealthLoop() }
        if !SpeakLiveActivityManager.isActive {
            SpeakLiveActivityManager.start()
        }
        pushLiveActivity(force: true)
        if !isMuted, !holdMicForTTS, !isBusy, !voice.verifyListeningPipeline() {
            if case .speaking = voice.phase { return }
            beginReturnToListening(settleSeconds: 0.15)
        }
        statusLine = isMuted
            ? "Stumm · Live Activity aktiv"
            : (voice.verifyListeningPipeline()
                ? "Voice AI · Sperrbildschirm / Island"
                : "NOCO hört zu…")
    }

    /// Reliable re-listen after TTS (debounce + settle delay).
    private func scheduleResumeListening(after delay: TimeInterval) {
        beginReturnToListening(settleSeconds: delay)
    }

    /// Single owner of speak→listen: wait for TTS to leave speaking, hard-reinit audio, open mic.
    private func beginReturnToListening(settleSeconds: TimeInterval) {
        resumeTask?.cancel()
        resumeGeneration &+= 1
        let generation = resumeGeneration
        resumeTaskStartedAt = Date()
        let settle = max(0.05, settleSeconds)
        VoiceDebugLog.event("RECOVERY", "return_to_listen gen=\(generation)")
        resumeTask = Task { [weak self] in
            for _ in 0..<200 {
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard let self, !Task.isCancelled else { return }
                guard await MainActor.run(body: { self.resumeGeneration == generation }) else { return }
                let stillSpeaking = await MainActor.run { () -> Bool in
                    self.voice.forceFinishIfSpeakingStuck(maxDuration: 90)
                    if case .speaking = self.voice.phase { return true }
                    return false
                }
                if !stillSpeaking { break }
            }
            let bg = await MainActor.run { UIApplication.shared.applicationState != .active }
            // Background needs more settle after TTS before mic/STT will attach.
            let tail = settle + (bg ? 0.35 : 0.08)
            try? await Task.sleep(nanoseconds: UInt64(tail * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                guard self.resumeGeneration == generation else { return }
                self.finishReturnToListening(generation: generation)
            }
        }
    }

    private func finishReturnToListening(generation: UInt64) {
        guard resumeGeneration == generation else { return }
        guard isRunning, !isExiting else {
            setHoldMicForTTS(false)
            if resumeGeneration == generation {
                resumeTask = nil
                resumeTaskStartedAt = nil
            }
            return
        }
        if case .speaking = voice.phase {
            voice.stopSpeaking(notifyFinished: false)
        }
        setHoldMicForTTS(false)
        setBusy(false)
        listenRetryCount = 0
        connection?.liveScreen.suppressAutoVision = true
        VoiceDebugLog.event("LISTENING_RESTART", "hard_reinit")
        resumeListening(forceHardReinit: true)
        // Keep resumeTask alive until second-chance settles (prevents health-loop double schedule).
        resumeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self else { return }
            guard self.resumeGeneration == generation else { return }
            guard self.isRunning, !self.isExiting, !self.holdMicForTTS, !self.isMuted else {
                if self.resumeGeneration == generation {
                    self.resumeTask = nil
                    self.resumeTaskStartedAt = nil
                }
                return
            }
            if !self.voice.isActivelyListening {
                VoiceDebugLog.event("RECOVERY", "second_chance_mic")
                self.resumeListening(forceHardReinit: true)
            }
            await self.drainPendingUtterance()
            if self.resumeGeneration == generation {
                self.resumeTask = nil
                self.resumeTaskStartedAt = nil
            }
        }
    }

    /// Poll until TTS leaves speaking, then resume mic (only if still in session).
    private func startSpeakWatchdog() {
        beginReturnToListening(settleSeconds: 0.28)
    }

    private func resumeListening(forceHardReinit: Bool = false) {
        // Allow mic reopen even during brief PC blips — utterance send handles offline.
        guard isRunning else { return }
        guard !isExiting, !holdMicForTTS else { return }
        guard !isMuted else {
            statusLine = "Stumm — tippe Mute aus zum Sprechen"
            voice.phase = .idle
            sessionPhase = .idle
            pushLiveActivity(force: true)
            return
        }
        guard !isBusy else {
            beginReturnToListening(settleSeconds: 0.15)
            return
        }
        if case .speaking = voice.phase {
            beginReturnToListening(settleSeconds: 0.25)
            return
        }
        if voice.verifyListeningPipeline(), !forceHardReinit {
            listenRetryCount = 0
            sessionPhase = .listening
            assistantPhase = pendingToolConfirm == nil ? .listening : .awaitingConfirm
            pushLiveActivity(force: true)
            return
        }
        do {
            if forceHardReinit {
                try voice.hardReinitAudioForListen()
            } else {
                try voice.activateListeningAfterTTS()
            }
            try voice.startListening(autoEnd: true)
            // Only claim Listening when the pipeline is actually live.
            guard voice.verifyListeningPipeline() else {
                throw VoiceService.ListenError.micNotReady
            }
            listenRetryCount = 0
            sessionPhase = .listening
            assistantPhase = pendingToolConfirm == nil ? .listening : .awaitingConfirm
            statusLine = pendingToolConfirm?.confirmationQuestion ?? "NOCO hört zu"
            VoiceAISessionState.publish(active: true, micOn: true, islandOn: SpeakLiveActivityManager.isActive)
            VoiceDebugLog.event("LISTENING_START", "verified")
            pushLiveActivity(force: true)
            Task { await drainPendingUtterance() }
        } catch {
            listenRetryCount += 1
            sessionPhase = .recovering
            assistantPhase = .idle
            statusLine = listenRetryCount <= 2
                ? "Zuhören unterbrochen — nochmal…"
                : "NOCO hört wieder zu…"
            VoiceDebugLog.event("VOICE_ERROR", error.localizedDescription)
            VoiceDebugLog.event("VOICE_RECOVERY", "retry_\(listenRetryCount)")
            let backoff = min(1.2, 0.18 + Double(listenRetryCount) * 0.18)
            beginReturnToListening(settleSeconds: backoff)
        }
    }

    private func enqueueUtterance(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Drop empty/noise fragments — never send blank Speak requests.
        let meaningful = trimmed.filter { $0.isLetter || $0.isNumber }
        guard meaningful.count >= 2 || trimmed.count >= 3 else {
            VoiceDebugLog.event("SPEECH_END", "ignored_noise")
            return
        }
        VoiceDebugLog.event("SPEECH_END", String(trimmed.prefix(48)))
        // Never accept speech while shutting down.
        if isExiting { return }
        // During TTS: only exit phrases interrupt; otherwise queue one follow-up.
        if holdMicForTTS || sessionPhase == .speaking || (voice.phase == .speaking) {
            let intent = SpeakIntentEngine.classify(
                trimmed,
                cameraOn: visionCameraEnabled,
                screenShareOn: screenShareEnabled,
                hasPendingFrame: pendingVisionJPEG != nil
            )
            if case .endSpeak = intent.action {
                setHoldMicForTTS(false)
                setBusy(false)
                invalidateTurn()
                connection?.chat.cancelSpeakSend()
                voice.softStopSpeaking(notifyFinished: false)
                await exitVoiceAI(spokenFarewell: true)
                return
            }
            pendingUtterance = trimmed
            statusLine = "Merke mir das…"
            return
        }
        // Only gate on real work — VoiceService sets .processing before callback,
        // which previously parked every utterance forever in pendingUtterance.
        if isBusy || sessionPhase == .processing {
            pendingUtterance = trimmed
            statusLine = "Einen Moment…"
            return
        }
        await handleUtterance(trimmed)
        if let next = pendingUtterance {
            pendingUtterance = nil
            await handleUtterance(next)
        }
    }

    /// User spoke over the assistant — soft-stop reply, prioritize their turn.
    private func handleBargeIn(_ text: String) async {
        guard isRunning, !isExiting else { return }
        statusLine = "Ich höre zu…"
        sessionPhase = .listening
        assistantPhase = .listening
        pushLiveActivity(force: true)

        let intent = SpeakIntentEngine.classify(
            text,
            cameraOn: visionCameraEnabled,
            screenShareOn: screenShareEnabled,
            hasPendingFrame: pendingVisionJPEG != nil
        )
        if case .endSpeak = intent.action {
            await exitVoiceAI(spokenFarewell: true)
            return
        }
        // Brief settle so TTS audio route releases before the next turn.
        try? await Task.sleep(nanoseconds: 140_000_000)
        guard isRunning, !isExiting else { return }
        await handleUtterance(text)
    }

    private func handleUtterance(_ text: String) async {
        guard isRunning, !isBusy, !holdMicForTTS, !isExiting, let connection else {
            if isBusy && !holdMicForTTS && !isExiting {
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
            await exitVoiceAI(spokenFarewell: true)
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
        let turn = beginTurn()
        setBusy(true)
        sessionPhase = .processing
        VoiceDebugLog.event("REQUEST_SENT", String(originalText.prefix(48)))
        mapAssistantPhase(for: intent)
        statusLine = intent.statusLine
        voice.phase = .processing
        pushLiveActivity(force: true)
        HapticService.send()
        guard turnIsLive(turn) else {
            setBusy(false)
            return
        }

        switch intent.action {
        case .endSpeak:
            setBusy(false)
            await exitVoiceAI(spokenFarewell: true)
            return

        case .screenMemory:
            await handleScreenMemory(connection: connection, turn: turn)
            return

        case .createImage(let prompt):
            await handleImageCreate(prompt: prompt, ack: intent.spokenAck, connection: connection, turn: turn)
            return

        case .runAgent(let goal):
            await handleAgent(goal: goal, ack: intent.spokenAck, connection: connection, turn: turn)
            return

        case .magicEraser:
            await handleMagicEraser(ack: intent.spokenAck, connection: connection, turn: turn)
            return

        case .summarize:
            await handleSummarize(originalText: originalText, style: intent.style, connection: connection, turn: turn)
            return

        case .visionAnalyze:
            await handleVision(originalText: originalText, connection: connection, turn: turn)
            return

        case .conversation(let depth):
            await handleConversation(
                originalText: originalText,
                depth: depth,
                style: intent.style,
                useLiveKnowledge: intent.useLiveKnowledge,
                ack: intent.spokenAck,
                connection: connection,
                turn: turn
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

    private func handleScreenMemory(connection: ConnectionStore, turn: UInt64) async {
        guard turnIsLive(turn) else { setBusy(false); return }
        let memory = connection.liveScreen.sessionSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let briefing = connection.liveScreen.contextBriefing.trimmingCharacters(in: .whitespacesAndNewlines)
        let recall = !memory.isEmpty ? memory : briefing
        if !recall.isEmpty {
            let reply = "Vorhin auf dem Bildschirm:\n\n\(recall)"
            await finishWithReply(reply, connection: connection, turn: turn)
        } else {
            await handleConversation(
                originalText: "Was war zuletzt auf dem Bildschirm?",
                depth: .flash,
                style: SpeakStyleHints(),
                useLiveKnowledge: false,
                ack: "",
                connection: connection,
                turn: turn
            )
        }
    }

    private func handleImageCreate(prompt: String, ack: String, connection: ConnectionStore, turn: UInt64) async {
        guard turnIsLive(turn) else { setBusy(false); return }
        assistantPhase = .creatingImage
        statusLine = SpeakActivityPhase.creatingImage.title
        pushLiveActivity(force: true)
        if !ack.isEmpty {
            await speakFillerPhrase(ack, turn: turn)
            guard turnIsLive(turn) else { setBusy(false); return }
            assistantPhase = .creatingImage
            statusLine = SpeakActivityPhase.creatingImage.title
            pushLiveActivity(force: true)
        }

        connection.chat.setMode(.image)
        let reply = await connection.chat.sendAndReturnReply(prompt, modeOverride: .image, speak: false)
        guard turnIsLive(turn) else { setBusy(false); return }
        let spoken = reply?.trimmingCharacters(in: .whitespacesAndNewlines)
        let final = (spoken?.isEmpty == false)
            ? spoken!
            : "Das Bild ist fertig — du findest es im Chat."
        await finishWithReply(final, connection: connection, turn: turn)
    }

    private func handleAgent(goal: String, ack: String, connection: ConnectionStore, turn: UInt64) async {
        guard turnIsLive(turn) else { setBusy(false); return }
        assistantPhase = .agentWorking
        statusLine = SpeakActivityPhase.agentWorking.title
        pushLiveActivity(force: true)
        if !ack.isEmpty {
            await speakFillerPhrase(ack, turn: turn)
            guard turnIsLive(turn) else { setBusy(false); return }
            assistantPhase = .agentWorking
            statusLine = SpeakActivityPhase.agentWorking.title
            pushLiveActivity(force: true)
        }

        connection.chat.setMode(.agent)
        let reply = await connection.chat.sendAndReturnReply(goal, modeOverride: .agent, speak: false)
        guard turnIsLive(turn) else { setBusy(false); return }
        let spoken: String
        if let reply, !reply.isEmpty {
            spoken = String(reply.prefix(900))
        } else {
            spoken = "Die Aufgabe läuft im Chat weiter. Schau dort kurz nach."
        }
        await finishWithReply(spoken, connection: connection, turn: turn)
    }

    private func handleMagicEraser(ack: String, connection: ConnectionStore, turn: UInt64) async {
        guard turnIsLive(turn) else { setBusy(false); return }
        assistantPhase = .thinking
        statusLine = "✨ Öffne Magischen Radierer…"
        pushLiveActivity(force: true)
        connection.pendingOpenEraser = true
        connection.pendingTab = 1
        showSpeakUI = false
        await finishWithReply(ack.isEmpty ? "Ich öffne den Magischen Radierer." : ack, connection: connection, turn: turn)
    }

    private func handleSummarize(originalText: String, style: SpeakStyleHints, connection: ConnectionStore, turn: UInt64) async {
        guard turnIsLive(turn) else { setBusy(false); return }
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
            speak: true,
            displayText: originalText
        )
        guard turnIsLive(turn) else { setBusy(false); return }
        await finishWithReply(reply ?? "", connection: connection, allowRetry: originalText, turn: turn)
    }

    private func handleVision(originalText: String, connection: ConnectionStore, turn: UInt64) async {
        guard turnIsLive(turn) else { setBusy(false); return }
        assistantPhase = .vision
        connection.liveScreen.suppressAutoVision = true
        statusLine = SpeakActivityPhase.vision.title
        pushLiveActivity(force: true)
        try? await Task.sleep(nanoseconds: 120_000_000)
        guard turnIsLive(turn) else { setBusy(false); return }

        var jpeg = pendingVisionJPEG
        pendingVisionJPEG = nil
        // Prefer a fresh frame when camera/screen is live — seamless Vision.
        if jpeg == nil, let image = visionFrameProvider?() {
            jpeg = image.jpegData(compressionQuality: 0.78)
        }
        if jpeg == nil, screenShareEnabled,
           let preview = connection.liveScreen.latestPreview,
           let data = preview.jpegData(compressionQuality: 0.78) {
            jpeg = data
        }
        if jpeg == nil, screenShareEnabled, let screenJPEG = connection.liveScreen.latestJPEG {
            jpeg = screenJPEG
        }

        guard let jpeg else {
            let tip = visionCameraEnabled || screenShareEnabled
                ? "Ich brauche noch ein klares Bild — tippe kurz auf Snapshot."
                : "Aktiviere Kamera oder Bildschirm, dann frag nochmal."
            await finishWithReply(tip, connection: connection, turn: turn)
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
        guard turnIsLive(turn) else { setBusy(false); return }
        await finishWithReply(reply ?? "", connection: connection, allowRetry: originalText, turn: turn)
    }

    private func handleConversation(
        originalText: String,
        depth: AIMode,
        style: SpeakStyleHints,
        useLiveKnowledge: Bool,
        ack: String,
        connection: ConnectionStore,
        turn: UInt64
    ) async {
        guard turnIsLive(turn) else { setBusy(false); return }
        if useLiveKnowledge {
            connection.chat.armLiveKnowledge(.web)
            assistantPhase = .webSearch
            statusLine = SpeakActivityPhase.webSearch.title
            pushLiveActivity(force: true)
            let filler = ack.isEmpty ? SpeakIntentEngine.randomWebAck() : ack
            await speakFillerPhrase(filler, turn: turn)
            guard turnIsLive(turn) else { setBusy(false); return }
            assistantPhase = .webSearch
            statusLine = SpeakActivityPhase.webSearch.title
            pushLiveActivity(force: true)
        } else {
            assistantPhase = .thinking
            statusLine = SpeakActivityPhase.thinking.title
            pushLiveActivity(force: true)
            if !ack.isEmpty {
                await speakFillerPhrase(ack, turn: turn)
                guard turnIsLive(turn) else { setBusy(false); return }
                assistantPhase = .thinking
                statusLine = SpeakActivityPhase.thinking.title
                pushLiveActivity(force: true)
            }
        }
        let prompt = VoiceService.speakPrompt(originalText, depth: depth, style: style)
        let reply = await connection.chat.sendAndReturnReply(
            prompt,
            modeOverride: depth,
            speak: true,
            displayText: originalText
        )
        guard turnIsLive(turn) else { setBusy(false); return }
        await finishWithReply(reply ?? "", connection: connection, allowRetry: originalText, turn: turn)
    }

    private func finishWithReply(
        _ reply: String,
        connection: ConnectionStore,
        allowRetry: String? = nil,
        turn: UInt64? = nil
    ) async {
        guard turnIsLive(turn) else {
            setBusy(false)
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
            guard turnIsLive(turn) else { setBusy(false); return }
            let prompt = VoiceService.speakPrompt(allowRetry, depth: .flash, style: SpeakStyleHints())
            resolved = (await connection.chat.sendAndReturnReply(
                prompt,
                modeOverride: .flash,
                speak: true,
                displayText: allowRetry
            ) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard turnIsLive(turn) else { setBusy(false); return }
            if resolved.isEmpty {
                let msg = Self.friendlySpeakError(connection.chat.lastError ?? "")
                statusLine = msg
                assistantPhase = .error
                voice.phase = .error(msg)
                pushLiveActivity(force: true)
                if voice.autoSpeakReplies, consecutiveFailures <= 2 {
                    setHoldMicForTTS(true)
                    setBusy(true)
                    assistantPhase = .speaking
                    // No barge-in — echo was cutting TTS mid-sentence on Island/home.
                    voice.speak(msg, allowBargeIn: false)
                    startSpeakWatchdog()
                } else {
                    setBusy(false)
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
            guard turnIsLive(turn) else { setBusy(false); return }
            // Always speak in Voice AI — hold mic until TTS fully finishes.
            statusLine = SpeakActivityPhase.speaking.title
            assistantPhase = .speaking
            pushLiveActivity(force: true)
            resumeTask?.cancel()
            setHoldMicForTTS(true)
            setBusy(true)
            connection.liveScreen.suppressAutoVision = true
            VoiceDebugLog.event("TTS_START", String(resolved.prefix(48)))
            VoiceDebugLog.event("REQUEST_RECEIVED", "chars=\(resolved.count)")
            // Barge-in off: prevents TTS cutoff from mic echo while speaking on home screen.
            voice.speak(resolved, allowBargeIn: false)
            startSpeakWatchdog()
        } else {
            setBusy(false)
            sessionPhase = .listening
            assistantPhase = .listening
            scheduleResumeListening(after: 0.2)
            await drainPendingUtterance()
        }
    }

    /// Short spoken bridge while work continues — does not resume the mic.
    private func speakFillerPhrase(_ text: String, turn: UInt64? = nil) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, voice.autoSpeakReplies else { return }
        guard turnIsLive(turn) else { return }
        resumeTask?.cancel()
        assistantPhase = .speaking
        lastReply = trimmed
        statusLine = trimmed
        pushLiveActivity(force: true)
        // Short ack — no barge-in (avoids racing the in-flight turn).
        voice.speak(trimmed, allowBargeIn: false)
        for _ in 0..<100 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard turnIsLive(turn) else {
                voice.stopSpeaking(notifyFinished: false)
                return
            }
            voice.forceFinishIfSpeakingStuck(maxDuration: 8)
            if case .speaking = voice.phase { continue }
            break
        }
        if case .speaking = voice.phase {
            voice.stopSpeaking(notifyFinished: false)
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
            setHoldMicForTTS(true)
            setBusy(true)
            voice.speak(text, allowBargeIn: false)
            startSpeakWatchdog()
        } else {
            setBusy(false)
            scheduleResumeListening(after: 0.2)
            await drainPendingUtterance()
        }
    }

    // Legacy path removed — intent engine owns routing.

    private func drainPendingUtterance() async {
        guard let next = pendingUtterance, isRunning, !isBusy, !holdMicForTTS, !isExiting else { return }
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
            live.autoAssistEnabled = true
            // While Voice AI runs, keep vision quiet so it cannot steal the audio turn.
            live.suppressAutoVision = isRunning
        }
        statusLine = isRunning ? "Bildschirm aus · nur Sprache" : "Voice AI bereit"
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
            case .listening:
                // Never show Listening on Island unless STT pipeline is really live.
                phase = voice.verifyListeningPipeline() ? .listening : .idle
            case .processing:
                if assistantPhase == .webSearch {
                    phase = .webSearch
                } else {
                    phase = assistantPhase == .thinking ? .thinking : .processing
                }
            case .speaking: phase = .speaking
            case .error: phase = .error
            case .idle:
                if isMuted {
                    phase = .idle
                } else if sessionPhase == .recovering {
                    phase = .processing
                } else if voice.verifyListeningPipeline() {
                    phase = .listening
                } else {
                    phase = .idle
                }
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
            titleOverride: islandTitle(for: phase)
        )
    }

    private func islandTitle(for phase: SpeakActivityPhase) -> String {
        let s = statusLine.lowercased()
        if s.contains("voice ai aktiviert") || s.contains("noco voice ai aktiviert") {
            return "NOCO Voice AI"
        }
        if s.contains("voice ai beendet") {
            return "Voice AI beendet"
        }
        // Prefer live phase titles — avoid stale "NOCO spricht" while already listening again.
        return phase.title
    }
}

