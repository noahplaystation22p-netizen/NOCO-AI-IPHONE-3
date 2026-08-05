import Foundation
import SwiftUI
import UIKit

/// App-scoped Speak session so audio + Live Activity survive leaving the Speak UI.
@MainActor
final class SpeakSessionController: ObservableObject {
    let voice = VoiceService()

    @Published var isRunning = false
    @Published var lastReply = ""
    @Published var statusLine = "Speak bereit"
    @Published var showSpeakUI = false
    @Published var isMuted = false

    private weak var connection: ConnectionStore?
    private var isBusy = false
    private var wired = false
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private var resumeTask: Task<Void, Never>?

    func bind(connection: ConnectionStore) {
        self.connection = connection
        guard !wired else { return }
        wired = true
        voice.onAutoUtterance = { [weak self] text in
            Task { await self?.handleUtterance(text) }
        }
        voice.onSpeakFinished = { [weak self] in
            self?.scheduleResumeListening(after: 0.45)
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
        do {
            // Live Activity banner + Island immediately
            SpeakLiveActivityManager.start()
            try voice.activateBackgroundAudioSession()
            isRunning = true
            isMuted = false
            voice.setMuted(false)
            voice.sessionActive = true
            beginBackgroundKeepAlive()
            try voice.startListening(autoEnd: true)
            statusLine = "Zuhören — Pause sendet automatisch"
            pushLiveActivity(force: true)
            HapticService.medium()
        } catch {
            isRunning = false
            endBackgroundKeepAlive()
            voice.phase = .error(error.localizedDescription)
            statusLine = "Mikrofon-Fehler"
            SpeakLiveActivityManager.end()
        }
    }

    func stop() {
        resumeTask?.cancel()
        resumeTask = nil
        isRunning = false
        isMuted = false
        voice.setMuted(false)
        voice.sessionActive = false
        voice.stopSpeaking(notifyFinished: false)
        voice.stopListening(cancel: true)
        endBackgroundKeepAlive()
        SpeakLiveActivityManager.end()
        voice.phase = .idle
        statusLine = "Speak gestoppt"
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
            statusLine = "Mic an — sprich, Pause sendet"
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
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard let self, !Task.isCancelled else { return }
                let speaking = await MainActor.run {
                    if case .speaking = self.voice.phase { return true }
                    return false
                }
                if !speaking { break }
            }
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.resumeListening() }
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
            // Retry shortly when chat round-trip still finishing
            scheduleResumeListening(after: 0.35)
            return
        }
        do {
            try voice.activateBackgroundAudioSession()
            try voice.startListening(autoEnd: true)
            statusLine = "Wieder Zuhören…"
            pushLiveActivity(force: true)
        } catch {
            statusLine = "Zuhören unterbrochen — nochmal versuchen"
            scheduleResumeListening(after: 0.8)
        }
    }

    private func handleUtterance(_ text: String) async {
        guard isRunning, !isBusy, let connection else { return }
        guard !isMuted else { return }
        isBusy = true
        defer { isBusy = false }

        statusLine = "Intelligence Sync…"
        voice.phase = .processing
        pushLiveActivity(force: true)
        HapticService.send()

        let prompt = VoiceService.voiceOnlyPrompt(text)
        let reply = await connection.chat.sendAndReturnReply(prompt, modeOverride: .flash, speak: true)

        guard isRunning else { return }

        if let reply, !reply.isEmpty {
            lastReply = reply
            if voice.autoSpeakReplies {
                statusLine = "Spoken Reply…"
                pushLiveActivity(force: true)
                resumeTask?.cancel()
                voice.speak(reply)
                // Watchdog: if TTS delegate misses finish, still resume after speech ends
                startSpeakWatchdog()
            } else {
                voice.phase = .idle
                scheduleResumeListening(after: 0.25)
            }
        } else {
            let msg = connection.chat.lastError ?? "Keine Antwort"
            statusLine = msg
            voice.phase = .error(msg)
            pushLiveActivity(force: true)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if isRunning { scheduleResumeListening(after: 0.2) }
        }
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
