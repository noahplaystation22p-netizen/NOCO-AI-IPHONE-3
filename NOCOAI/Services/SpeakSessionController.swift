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
        case starting
        case listening
        case processing
        case speaking
        case restartingListening
        case recovering
        case stopping
        case stopped
        case error
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
    /// Single authoritative visual source for Speak (screen XOR camera XOR none).
    @Published private(set) var visualMode: VisualMode = .none
    /// Cached analysis for follow-up questions — not dumped into chat history.
    @Published private(set) var visualContext: VisualContext?
    /// One-shot JPEG waiting to be analyzed with the next relevant utterance.
    @Published var pendingVisionJPEG: Data?
    /// Rich assistant phase for Island + Speak UI (beyond mic phase).
    @Published var assistantPhase: SpeakAssistantPhase = .idle
    /// Safety-mode pending tool confirmation.
    @Published var pendingToolConfirm: SpeakIntent?
    private var pendingToolOriginal: String?
    var visionFrameProvider: (() -> UIImage?)?
    /// Ignores stale vision async completions.
    private var visualGeneration: UInt64 = 0

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
    /// Debounce lifecycle presence so inactive/background/foreground don't stampede audio.
    private var lastPresenceAt: Date?
    /// One queued utterance while NOCO is processing / speaking.
    private var pendingUtterance: String?
    private var consecutiveFailures = 0
    private var lastIslandTranscript: String = ""
    private var lastIslandSpokenText: String = ""
    private var listenRetryCount = 0
    private var cancellables = Set<AnyCancellable>()
    /// While true: never reopen the mic (reply TTS / farewell in progress).
    private var holdMicForTTS = false
    private var holdMicStartedAt: Date?
    /// Set when shutting down Voice AI — skip resume-listening.
    private var isExiting = false
    /// Unique per Voice start (Shortcut / in-app). Independent of chat history.
    private(set) var voiceSessionId: String = ""
    /// Conversation bound to this Voice session (fresh on each Shortcut start).
    private(set) var voiceConversationId: String?

    /// Live Screen / vision gate — true while Speak is busy or TTS is playing.
    var isBusyForVision: Bool {
        if isBusy { return true }
        switch sessionPhase {
        case .processing, .speaking, .restartingListening, .recovering, .stopping, .exiting: return true
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
        if on { transition(to: .speaking, reason: "hold_mic_tts") }
    }

    /// Single writer for sessionPhase — logs every transition for race diagnosis.
    private func transition(to newPhase: SessionPhase, reason: String) {
        let old = sessionPhase
        guard old != newPhase else { return }
        // Reject noisy transitions while a normal TTS→listen resume owns the mic.
        if resumeTask != nil,
           (newPhase == .recovering),
           (old == .speaking || old == .restartingListening) {
            VoiceDebugLog.event("TRANSITION_REJECTED", "old=\(old) new=\(newPhase) reason=\(reason) resume_inflight")
            return
        }
        sessionPhase = newPhase
        VoiceDebugLog.event("STATE_CHANGE", "old=\(old) new=\(newPhase) \(reason)")
    }

    func bind(connection: ConnectionStore) {
        self.connection = connection
        guard !wired else { return }
        wired = true
        voice.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            self.objectWillChange.send()
            // Push Island immediately when the live transcript grows — Lock Screen
            // already felt snappy; Island was lagging behind throttled meter updates.
            let live = self.voice.liveTranscript
            if live != self.lastIslandTranscript {
                self.lastIslandTranscript = live
                if self.isRunning, !live.isEmpty,
                   self.assistantPhase == .listening || self.sessionPhase == .listening {
                    self.pushLiveActivity(force: true)
                }
            }
            // Mirror TTS-synced visible text onto the Island (never dump full lastReply).
            let spoken = self.voice.spokenVisibleText
            if spoken != self.lastIslandSpokenText {
                self.lastIslandSpokenText = spoken
                if self.isRunning, self.assistantPhase == .speaking || self.sessionPhase == .speaking
                    || self.voice.phase == .speaking {
                    self.pushLiveActivity(force: true)
                }
            }
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
            // Mid-turn bridge ("Ich schaue kurz nach") finishes while still busy —
            // never reopen listening / never leave Island stuck between webSearch & listen.
            if self.isBusy, !self.holdMicForTTS {
                VoiceDebugLog.event("TTS_END", "bridge_keep_busy")
                VoiceDebugLog.event("RECOVERY_SKIPPED", "normal_transition filler_tts")
                return
            }
            // Deterministic speaking → restartingListening.
            self.connection?.liveScreen.suppressAutoVision = true
            self.transition(to: .restartingListening, reason: "tts_end")
            self.assistantPhase = .listening
            if self.resumeTask == nil {
                self.beginReturnToListening(settleSeconds: 0.18)
            } else {
                self.resumeTaskStartedAt = Date()
            }
            VoiceDebugLog.event("TTS_END", "speaking→listening")
            self.pushLiveActivity(force: true)
            self.objectWillChange.send()
        }
    }

    func openUI() {
        showSpeakUI = true
    }

    /// Shortcut / Action Button start — always opens a fresh conversation context.
    func startFromShortcut(freshConversation: Bool = true) {
        Task { @MainActor in
            if freshConversation, let connection {
                VoiceDebugLog.event("SHORTCUT_START", "fresh_conversation")
                await connection.chat.beginCleanSession()
                voiceConversationId = connection.chat.activeConversationId
                VoiceDebugLog.event(
                    "CONVERSATION_CREATED",
                    "id=\(voiceConversationId ?? "pending_stream")"
                )
            }
            start(source: "shortcut")
        }
    }

    func start(source: String = "ui") {
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
            await startAsync(connection: connection, source: source)
        }
    }

    private func startAsync(connection: ConnectionStore, source: String = "ui") async {
        if isRunning, !isExiting {
            ensureBackgroundPresence()
            return
        }
        isExiting = false
        setHoldMicForTTS(false)
        setBusy(false)
        voiceSessionId = UUID().uuidString
        if source != "shortcut" {
            voiceConversationId = connection.chat.activeConversationId
        }
        VoiceDebugLog.event("SESSION_CREATED", "id=\(voiceSessionId) source=\(source)")
        if let cid = voiceConversationId {
            VoiceDebugLog.event("CONVERSATION_BOUND", "id=\(cid)")
        }
        transition(to: .starting, reason: "start_\(source)")
        if source == "shortcut" {
            VoiceDebugLog.event("BACKGROUND_START", "island_first")
        }
        // Live Activity = status mirror only (not the voice engine).
        VoiceDebugLog.event("LIVE_ACTIVITY_START", "attempt")
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
            transition(to: .listening, reason: "mic_ready")
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
            transition(to: .error, reason: "mic_error")
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
        transition(to: .stopping, reason: "stop")
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
        visualMode = .none
        visualContext = nil
        visualGeneration &+= 1
        visionFrameProvider = nil
        pendingVisionJPEG = nil
        pendingToolConfirm = nil
        pendingToolOriginal = nil
        pendingUtterance = nil
        transition(to: .stopped, reason: "stopped")
        assistantPhase = .idle
        statusLine = "Voice AI beendet"
        VoiceDebugLog.event("SESSION_ENDED", "id=\(voiceSessionId)")
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
        VoiceDebugLog.event("SHORTCUT_STOP", "silent")
        guard isRunning || showSpeakUI || VoiceAISessionState.isActive else {
            VoiceAISessionState.publish(active: false, micOn: false, islandOn: false)
            SpeakLiveActivityManager.end()
            return
        }
        isExiting = true
        setHoldMicForTTS(false)
        invalidateTurn()
        connection?.chat.cancelSpeakSend()
        resumeTask?.cancel()
        resumeTask = nil
        resumeTaskStartedAt = nil
        // Do not pre-cancel recognition/TTS here — stop() owns teardown once.
        statusLine = "Voice AI beendet"
        VoiceAISessionState.publish(active: false, micOn: false, islandOn: false)
        SpeakLiveActivityManager.update(
            phase: .idle,
            detail: "Voice AI beendet",
            level: 0.15,
            bars: [0.15, 0.18, 0.2, 0.18, 0.15, 0.12, 0.1],
            isOnline: false,
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
        visualMode = .none
        visualContext = nil
        visualGeneration &+= 1
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
            isOnline: false,
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
        visualMode = .none
        visualContext = nil
        visualGeneration &+= 1
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

        // A live TTS→listen transition owns the mic. Never race it with health recovery.
        if resumeTask != nil {
            return
        }

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
            transition(to: .restartingListening, reason: "stuck_busy")
            VoiceDebugLog.event("VOICE_RECOVERY", "stuck_busy")
            beginReturnToListening(settleSeconds: 0.08)
            return
        }

        // Speaking hold with NO resume in flight (true stuck after TTS).
        if holdMicForTTS || sessionPhase == .speaking {
            if case .speaking = voice.phase {
                voice.forceFinishIfSpeakingStuck(maxDuration: 120)
                return
            }
            let holdAge = holdMicStartedAt.map { Date().timeIntervalSince($0) } ?? 99
            guard holdAge > 8 else { return }
            setHoldMicForTTS(false)
            setBusy(false)
            transition(to: .restartingListening, reason: "stuck_hold")
            statusLine = "NOCO hört wieder zu…"
            VoiceDebugLog.event("VOICE_ERROR", "stuck_hold_forced")
            VoiceDebugLog.event("VOICE_RECOVERY", "health_force_listen")
            beginReturnToListening(settleSeconds: 0.08)
            return
        }

        guard !isBusy else { return }
        if case .speaking = voice.phase { return }
        if case .processing = voice.phase { return }
        if sessionPhase == .restartingListening { return }

        let bg = UIApplication.shared.applicationState != .active
        if voice.verifyListeningPipeline() {
            // Never proactive-refresh in background — that destroyed working STT (1110).
            if !bg {
                voice.refreshRecognitionIfStale(maxAge: 18)
            }
            if voice.verifyListeningPipeline() {
                transition(to: .listening, reason: "health_ok")
                if assistantPhase == .listening || assistantPhase == .idle {
                    assistantPhase = pendingToolConfirm == nil ? .listening : .awaitingConfirm
                }
            }
            return
        }

        // Phase said listening but pipeline is dead — reopen for real.
        transition(to: .restartingListening, reason: "pipeline_dead")
        statusLine = "NOCO hört wieder zu…"
        VoiceDebugLog.event("BACKGROUND_RECOVERY", "pipeline_not_active \(voice.pipelineDebugSummary())")
        beginReturnToListening(settleSeconds: bg ? 0.12 : 0.05)
    }

    func ensureBackgroundPresence() {
        guard isRunning else { return }
        if let last = lastPresenceAt, Date().timeIntervalSince(last) < 1.8 {
            VoiceDebugLog.event("BACKGROUND_ENTER", "ensure_presence_debounced")
            return
        }
        lastPresenceAt = Date()

        beginBackgroundKeepAlive()
        if bgRenewTask == nil { startBackgroundRenewLoop() }
        if listenHealthTask == nil { startListenHealthLoop() }

        let listeningOK = voice.verifyListeningPipeline()
        if listeningOK {
            // Soft presence: mic/STT already healthy — do not reconfigure audio.
            VoiceDebugLog.event("BACKGROUND_ENTER", "soft_presence \(voice.pipelineDebugSummary())")
            if !SpeakLiveActivityManager.isActive {
                SpeakLiveActivityManager.start()
            }
            pushLiveActivity(force: true)
            statusLine = isMuted ? "Stumm · Live Activity aktiv" : "Voice AI · Sperrbildschirm / Island"
            return
        }

        VoiceDebugLog.event("BACKGROUND_ENTER", "ensure_presence \(voice.pipelineDebugSummary())")
        try? voice.activateBackgroundAudioSession()
        if !SpeakLiveActivityManager.isActive {
            SpeakLiveActivityManager.start()
        }
        pushLiveActivity(force: true)

        // TTS_END / resumeTask own the transition — presence must not start a parallel recovery.
        if resumeTask != nil || holdMicForTTS {
            VoiceDebugLog.event("RECOVERY_SKIPPED", "normal_transition presence")
            return
        }
        if case .speaking = voice.phase { return }
        if case .processing = voice.phase { return }
        if !isMuted, !isBusy {
            beginReturnToListening(settleSeconds: 0.15)
        }
        statusLine = isMuted
            ? "Stumm · Live Activity aktiv"
            : "NOCO hört zu…"
    }

    /// Reliable re-listen after TTS (debounce + settle delay).
    private func scheduleResumeListening(after delay: TimeInterval) {
        beginReturnToListening(settleSeconds: delay)
    }

    /// Single owner of speak→listen: wait for TTS to leave speaking, hard-reinit audio, open mic.
    private func beginReturnToListening(settleSeconds: TimeInterval) {
        if let started = resumeTaskStartedAt,
           resumeTask != nil,
           Date().timeIntervalSince(started) < 1.6 {
            VoiceDebugLog.event("RECOVERY", "return_to_listen_already_pending")
            return
        }
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
        // Never hard-cut finished TTS. If somehow still speaking, wait — don't stopSpeaking.
        if case .speaking = voice.phase {
            VoiceDebugLog.event("RECOVERY_SKIPPED", "normal_transition tts_still_speaking")
            beginReturnToListening(settleSeconds: 0.18)
            return
        }
        setHoldMicForTTS(false)
        setBusy(false)
        listenRetryCount = 0
        connection?.liveScreen.suppressAutoVision = true
        // Soft reopen first — hard_reinit only if soft path fails (second chance).
        VoiceDebugLog.event("LISTENING_RESTART", "soft_after_tts")
        resumeListening(forceHardReinit: false)
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
                VoiceDebugLog.event("RECOVERY", "second_chance_hard_reinit")
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
            transition(to: .idle, reason: "muted")
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
            transition(to: .listening, reason: "pipeline_already_live")
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
            transition(to: .listening, reason: forceHardReinit ? "hard_reinit_ok" : "soft_reopen_ok")
            assistantPhase = pendingToolConfirm == nil ? .listening : .awaitingConfirm
            statusLine = pendingToolConfirm?.confirmationQuestion ?? "NOCO hört zu"
            lastIslandTranscript = ""
            VoiceAISessionState.publish(active: true, micOn: true, islandOn: SpeakLiveActivityManager.isActive)
            VoiceDebugLog.event("LISTENING_START", "verified")
            pushLiveActivity(force: true)
            Task { await drainPendingUtterance() }
        } catch {
            listenRetryCount += 1
            transition(to: .recovering, reason: "listen_fail")
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
        // Island: leave mic chrome immediately (do NOT flip sessionPhase here —
        // that would park the utterance in the processing gate below).
        if !holdMicForTTS, sessionPhase != .speaking, voice.phase != .speaking {
            assistantPhase = .thinking
            statusLine = SpeakActivityPhase.thinking.title
            pushLiveActivity(force: true)
        }
        // During TTS: only exit phrases interrupt; otherwise queue one follow-up.
        if holdMicForTTS || sessionPhase == .speaking || (voice.phase == .speaking) {
            let intent = SpeakIntentEngine.classify(
                trimmed,
                visualMode: effectiveVisualMode(),
                hasPendingFrame: pendingVisionJPEG != nil,
                hasVisualContext: visualContext != nil
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
        transition(to: .listening, reason: "barge_in")
        assistantPhase = .listening
        pushLiveActivity(force: true)

        let intent = SpeakIntentEngine.classify(
            text,
            visualMode: effectiveVisualMode(),
            hasPendingFrame: pendingVisionJPEG != nil,
            hasVisualContext: visualContext != nil
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
            visualMode: effectiveVisualMode(),
            hasPendingFrame: pendingVisionJPEG != nil,
            lastAssistantHadImage: connection.chat.messages.reversed().contains {
                $0.role == .assistant && ($0.localImageData != nil || $0.imageURL != nil)
            },
            hasVisualContext: visualContext != nil
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
        transition(to: .processing, reason: "request")
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
        let mode = effectiveVisualMode()
        VisualLog.event("VISUAL_QUERY_DETECTED", "\"\(originalText.prefix(80))\" mode=\(mode.logName)")

        assistantPhase = .vision
        connection.liveScreen.suppressAutoVision = true
        statusLine = SpeakActivityPhase.vision.title
        pushLiveActivity(force: true)
        try? await Task.sleep(nanoseconds: 80_000_000)
        guard turnIsLive(turn) else { setBusy(false); return }

        // Visual Mode off → never pretend we need a photo; ask to enable Screen/Live View.
        if mode == .none, pendingVisionJPEG == nil {
            VisualLog.event("VISUAL_CAPTURE_FAILED", "reason=no_visual_mode")
            await finishWithReply(
                "Aktiviere zuerst Screen View oder Live View in Speak — dann frag mich, was ich sehe.",
                connection: connection,
                turn: turn
            )
            return
        }

        let refresh = SpeakIntentEngine.visualRefreshReason(
            originalText,
            mode: mode,
            context: visualContext
        )
        if refresh == .none, let ctx = visualContext, !ctx.summary.isEmpty {
            VisualLog.event("VISUAL_CONTEXT_REUSED", "age=\(Int(ctx.age))s source=\(ctx.source.rawValue)")
            await answerFromVisualContext(originalText: originalText, context: ctx, connection: connection, turn: turn)
            return
        }
        if refresh != .none {
            VisualLog.event("VISUAL_CONTEXT_REFRESH_REQUIRED", "reason=\(refresh.rawValue)")
        }

        visualGeneration &+= 1
        let gen = visualGeneration

        VisualLog.event("VISUAL_CAPTURE_REQUESTED", "source=\(mode.logName)")
        let jpeg = await captureCurrentVisualFrame(mode: mode, connection: connection)
        guard turnIsLive(turn), gen == visualGeneration else { setBusy(false); return }

        guard let jpeg else {
            VisualLog.event("VISUAL_CAPTURE_FAILED", "source=\(mode.logName)")
            let tip: String
            if mode == .screen {
                tip = connection.liveScreen.broadcastWaiting || connection.liveScreen.latestPreview == nil
                    ? "Screen View wartet noch auf die Bildschirmübertragung. Tippe rot „Übertragen“ und wähle NOCO Live Screen — dann frag nochmal."
                    : "Ich konnte gerade keinen Bildschirm-Frame lesen. Kurz warten und nochmal fragen."
            } else {
                tip = "Live View hat gerade kein Kamerabild. Kurz warten und nochmal fragen."
            }
            await finishWithReply(tip, connection: connection, turn: turn)
            return
        }
        VisualLog.event("VISUAL_CAPTURE_SUCCESS", "source=\(mode.logName) bytes=\(jpeg.count)")

        statusLine = mode == .screen ? "NOCO analysiert Bildschirm…" : "NOCO analysiert…"
        pushLiveActivity(force: true)
        ImageLiveActivityManager.start(
            prompt: mode == .screen ? "Screen View · Speak" : "Live View · Speak",
            owner: .speakVision
        )
        ImageLiveActivityManager.update(
            progress: 0.35,
            status: "Analysiert…",
            insight: String(originalText.prefix(60)),
            etaSeconds: 8,
            phase: .rendering,
            force: true
        )

        VisualLog.event("VISUAL_ANALYSIS_STARTED", "source=\(mode.logName)")
        let ocrHint = mode == .screen
            ? connection.liveScreen.latestOCRPreview
            : ""
        let reply = await connection.chat.sendVisionForSpeak(
            jpeg: jpeg,
            userText: originalText,
            sourceLabel: mode == .screen ? "screen" : "camera",
            ocrHint: ocrHint
        )
        ImageLiveActivityManager.complete(prompt: "Vision fertig")
        guard turnIsLive(turn), gen == visualGeneration else { setBusy(false); return }

        if let reply, !reply.isEmpty {
            VisualLog.event("VISUAL_ANALYSIS_COMPLETE", "chars=\(reply.count)")
            visualContext = VisualContext(
                source: mode == .screen ? .screen : .camera,
                capturedAt: Date(),
                summary: String(reply.prefix(900)),
                relevantText: originalText,
                ocrSnippet: String(ocrHint.prefix(400)),
                generation: gen
            )
            VisualLog.event("VISUAL_CONTEXT_UPDATED", "source=\(mode.logName)")
            await finishWithReply(reply, connection: connection, turn: turn)
        } else {
            VisualLog.event("VISUAL_CAPTURE_FAILED", "reason=empty_reply")
            await finishWithReply(
                "Die Bildanalyse ist kurz fehlgeschlagen. Speak läuft weiter — frag gerne noch einmal.",
                connection: connection,
                turn: turn
            )
        }
    }

    private func answerFromVisualContext(
        originalText: String,
        context: VisualContext,
        connection: ConnectionStore,
        turn: UInt64
    ) async {
        guard turnIsLive(turn) else { setBusy(false); return }
        assistantPhase = .thinking
        statusLine = "NOCO denkt…"
        pushLiveActivity(force: true)
        let hidden = """
        [NOCO SPEAK · VISUAL CONTEXT — INTERN]
        Nutze NUR diesen gespeicherten visuellen Kontext. Kein neues Bild.
        Antworte kurz und natürlich auf Deutsch zum Vorlesen.

        \(context.briefing)

        Nutzerfrage: \(originalText)
        """
        let reply = await connection.chat.sendSpeakHiddenContext(
            userVisibleText: originalText,
            hiddenPrompt: hidden
        )
        guard turnIsLive(turn) else { setBusy(false); return }
        await finishWithReply(
            reply?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? reply!
                : "Dazu brauche ich einen frischen Blick — frag nochmal mit „Was siehst du jetzt?“.",
            connection: connection,
            turn: turn
        )
    }

    /// Resolves VisualMode; prefers explicit Speak toggles.
    private func effectiveVisualMode() -> VisualMode {
        if visualMode != .none { return visualMode }
        if screenShareEnabled { return .screen }
        if visionCameraEnabled { return .camera }
        return .none
    }

    private func setVisualMode(_ mode: VisualMode, reason: String) {
        let old = visualMode
        guard old != mode else {
            visionCameraEnabled = mode == .camera
            screenShareEnabled = mode == .screen
            return
        }
        visualMode = mode
        visionCameraEnabled = mode == .camera
        screenShareEnabled = mode == .screen
        if mode == .none || (old != .none && old != mode) {
            visualContext = nil
            pendingVisionJPEG = nil
        }
        VisualLog.event("VISUAL_MODE_CHANGED", "\(old.logName) -> \(mode.logName) | \(reason)")
        pushLiveActivity(force: true)
    }

    /// Event-based: grab ONE current frame from the active visual source.
    private func captureCurrentVisualFrame(mode: VisualMode, connection: ConnectionStore) async -> Data? {
        if let pending = pendingVisionJPEG {
            pendingVisionJPEG = nil
            return pending
        }
        switch mode {
        case .camera:
            if let image = visionFrameProvider?(),
               let jpeg = image.jpegData(compressionQuality: 0.78) {
                return jpeg
            }
            // Brief settle if camera just opened.
            try? await Task.sleep(nanoseconds: 180_000_000)
            if let image = visionFrameProvider?(),
               let jpeg = image.jpegData(compressionQuality: 0.78) {
                return jpeg
            }
            return nil
        case .screen:
            // Poll briefly for broadcast frames — do not claim "enable screen" if already waiting.
            for attempt in 0..<8 {
                if let preview = connection.liveScreen.latestPreview,
                   let jpeg = preview.jpegData(compressionQuality: 0.78) {
                    return jpeg
                }
                if let jpeg = connection.liveScreen.latestJPEG {
                    return jpeg
                }
                if attempt < 7 {
                    try? await Task.sleep(nanoseconds: 220_000_000)
                }
            }
            return nil
        case .none:
            return nil
        }
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
            transition(to: .listening, reason: "empty_reply")
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
        resumeTask = nil
        resumeTaskStartedAt = nil
        let previousPhase = assistantPhase
        assistantPhase = .speaking
        lastReply = trimmed
        statusLine = trimmed
        pushLiveActivity(force: true)
        // Bridge TTS must not fire onSpeakFinished → return-to-listen.
        voice.speakBridge(trimmed)
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
        // Restore tool / knowledge phase for Island while the PC works.
        assistantPhase = previousPhase == .speaking ? .thinking : previousPhase
        if assistantPhase == .idle || assistantPhase == .listening {
            assistantPhase = .thinking
        }
        pushLiveActivity(force: true)
        try? await Task.sleep(nanoseconds: 40_000_000)
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
        let mode = effectiveVisualMode()
        if mode == .screen {
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
            statusLine = "Kein Screen-Frame — Übertragung prüfen"
            HapticService.error()
            return
        }
        guard mode == .camera,
              let image = visionFrameProvider?(),
              let jpeg = image.jpegData(compressionQuality: 0.8) else {
            statusLine = "Kein Bild — Live View oder Screen View aktivieren"
            HapticService.error()
            return
        }
        pendingVisionJPEG = jpeg
        statusLine = "Momentaufnahme bereit"
        HapticService.imageSnap()
    }

    /// Enable Live Screen context inside Speak (Broadcast only — event-based analysis).
    func enableScreenShare() async {
        guard let connection else { return }
        let live = connection.liveScreen
        if !live.hasConsent {
            statusLine = "Live Screen Zustimmung nötig — einmalig in Studio → Live Screen"
            HapticService.error()
            connection.pendingOpenLiveScreen = true
            connection.pendingTab = 2
            return
        }
        do {
            if !live.isActive {
                try live.startSession()
            }
            // Speak owns vision timing — preview only, no auto vision spam.
            live.autoAssistEnabled = false
            live.suppressAutoVision = true
            setVisualMode(.screen, reason: "enable_screen_share")
            statusLine = live.broadcastWaiting || live.latestPreview == nil
                ? "Screen View · tippe rot „Übertragen“ → NOCO Live Screen"
                : "Screen View aktiv"
            HapticService.success()
        } catch {
            statusLine = (error as? LocalizedError)?.errorDescription ?? "Live Screen Start fehlgeschlagen"
            HapticService.error()
        }
    }

    func disableScreenShare() {
        setVisualMode(.none, reason: "disable_screen_share")
        if let live = connection?.liveScreen, live.isActive {
            live.autoAssistEnabled = false
            live.suppressAutoVision = true
            // Keep broadcast session for quick re-enable; Speak no longer consumes frames.
        }
        statusLine = isRunning ? "Screen View aus · nur Sprache" : "Voice AI bereit"
        HapticService.soft()
    }

    /// Called from Speak UI when camera Live View is toggled.
    func setCameraVisualMode(enabled: Bool) {
        if enabled {
            setVisualMode(.camera, reason: "enable_camera")
        } else if visualMode == .camera {
            setVisualMode(.none, reason: "disable_camera")
        }
    }

    func pushLiveActivity(force: Bool) {
        guard isRunning else { return }
        if !SpeakLiveActivityManager.isActive {
            SpeakLiveActivityManager.start()
        }

        let phase = resolveIslandPhase()
        let detail = resolveIslandDetail(for: phase)
        let (level, bars) = islandMeter(for: phase)
        SpeakLiveActivityManager.update(
            phase: phase,
            detail: detail,
            level: level,
            bars: bars,
            // Voice session active → always LIVE (never OFF from brief connection blips).
            isOnline: true,
            isMuted: isMuted,
            force: force,
            titleOverride: islandTitle(for: phase)
        )
    }

    /// Island must follow the authoritative session phase first.
    private func resolveIslandPhase() -> SpeakActivityPhase {
        // Speaking / TTS hold always wins — never leave "NOCO denkt" while audio plays.
        if holdMicForTTS || sessionPhase == .speaking || assistantPhase == .speaking {
            return .speaking
        }
        if case .speaking = voice.phase {
            return .speaking
        }
        if case .error = voice.phase {
            return .error
        }
        if sessionPhase == .error {
            return .error
        }
        if isMuted {
            return .idle
        }

        switch sessionPhase {
        case .processing:
            if assistantPhase == .webSearch { return .webSearch }
            if assistantPhase == .creatingImage { return .creatingImage }
            if assistantPhase == .agentWorking { return .agentWorking }
            if assistantPhase == .vision { return .vision }
            if assistantPhase == .awaitingConfirm { return .awaitingConfirm }
            return .thinking
        case .listening:
            return voice.verifyListeningPipeline() ? .listening : .listening
        case .restartingListening, .recovering, .starting:
            // Soft reopen after TTS — keep "hört zu", never flash "denkt".
            return .listening
        case .stopping, .stopped, .exiting, .idle:
            break
        case .speaking:
            return .speaking
        case .error:
            return .error
        }

        switch assistantPhase {
        case .creatingImage, .agentWorking, .vision, .awaitingConfirm, .webSearch:
            return assistantPhase.activityPhase
        case .thinking:
            if case .listening = voice.phase,
               !voice.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .listening
            }
            return .thinking
        case .speaking:
            return .speaking
        case .error:
            return .error
        case .listening, .idle:
            switch voice.phase {
            case .listening:
                return voice.verifyListeningPipeline() ? .listening : .idle
            case .processing:
                return .thinking
            case .speaking:
                return .speaking
            case .error:
                return .error
            case .idle:
                if voice.verifyListeningPipeline() {
                    return .listening
                }
                return .idle
            }
        }
    }

    private func resolveIslandDetail(for phase: SpeakActivityPhase) -> String {
        if isMuted {
            return phase == .speaking
                ? (voice.spokenVisibleText.isEmpty
                   ? (lastReply.isEmpty ? "Stumm · Wiedergabe…" : "Stumm · Wiedergabe…")
                   : voice.spokenVisibleText)
                : "Mic stumm — Mute aus zum Sprechen"
        }
        if pendingToolConfirm != nil {
            return pendingToolConfirm?.confirmationQuestion ?? "Bestätigung nötig"
        }
        switch phase {
        case .listening:
            let live = voice.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !live.isEmpty { return live }
            switch effectiveVisualMode() {
            case .screen: return "Screen View · Rede natürlich…"
            case .camera: return "Live View · Rede natürlich…"
            case .none: return "Rede natürlich…"
            }
        case .speaking:
            if !voice.spokenVisibleText.isEmpty {
                return voice.spokenVisibleText
            }
            return lastReply.isEmpty ? "Antwort wird vorgelesen…" : "…"
        case .thinking, .processing:
            return statusLine.isEmpty ? SpeakActivityPhase.thinking.title : statusLine
        case .webSearch:
            return statusLine.isEmpty ? "Live Knowledge · Quellen werden gelesen…" : statusLine
        case .creatingImage:
            return "Bildmodell arbeitet…"
        case .agentWorking:
            return "Plant, recherchiert und führt aus…"
        case .vision:
            switch effectiveVisualMode() {
            case .screen: return "NOCO analysiert den Bildschirm…"
            case .camera: return "NOCO analysiert die Kamera…"
            case .none: return "NOCO sieht…"
            }
        case .awaitingConfirm:
            return "Ja oder Nein sagen"
        case .error:
            if case .error(let m) = voice.phase { return m }
            return statusLine
        case .idle:
            return SpeakFullAccess.isEnabled ? "Vollzugriff · Assistent bereit" : "Bereit"
        }
    }

    /// Real mic bars while listening — boost quiet speech so Island reacts.
    private func islandMeter(for phase: SpeakActivityPhase) -> (Double, [Double]) {
        switch phase {
        case .listening:
            let raw = Double(voice.level)
            // Gate soft noise, then expand mid speech so compact bars jump alive.
            let gated = raw < 0.045 ? raw * 0.35 : min(1.0, pow(raw, 0.62) * 1.35)
            let step = max(voice.bands.count / 7, 1)
            var seven: [Double] = []
            for i in stride(from: 0, to: voice.bands.count, by: step) where seven.count < 7 {
                let b = Double(voice.bands[i])
                let boosted = b < 0.045 ? b * 0.4 : min(1.0, pow(b, 0.62) * 1.4)
                seven.append(max(boosted, gated * (0.55 + 0.08 * Double(seven.count))))
            }
            while seven.count < 7 { seven.append(gated) }
            return (gated, seven)
        case .speaking:
            let t = Date().timeIntervalSinceReferenceDate
            let bars = (0..<7).map { i in
                0.32 + 0.58 * abs(sin(t * 7.4 + Double(i) * 0.78))
            }
            return (0.62 + 0.28 * abs(sin(t * 5.6)), bars)
        case .thinking, .processing, .webSearch:
            let t = Date().timeIntervalSinceReferenceDate
            let bars = (0..<7).map { i in
                0.16 + 0.42 * abs(sin(t * 3.8 + Double(i) * 0.58))
            }
            return (0.32, bars)
        default:
            return (0.14, Array(repeating: 0.12, count: 7))
        }
    }

    private func islandTitle(for phase: SpeakActivityPhase) -> String {
        let s = statusLine.lowercased()
        if s.contains("voice ai aktiviert") || s.contains("noco voice ai aktiviert") {
            return "NOCO Voice AI"
        }
        if s.contains("voice ai beendet") {
            return "Voice AI beendet"
        }
        if phase == .vision {
            return "NOCO sieht…"
        }
        // Keep listening/speaking titles honest; decorate with Visual Mode when idle/listen.
        if phase == .listening || phase == .idle {
            switch effectiveVisualMode() {
            case .screen: return "NOCO Voice · Screen View"
            case .camera: return "NOCO Voice · Live View"
            case .none: break
            }
        }
        // Prefer live phase titles — avoid stale "NOCO spricht" while already listening again.
        return phase.title
    }
}

