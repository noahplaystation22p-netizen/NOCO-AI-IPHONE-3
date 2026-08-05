import Foundation
import SwiftUI

/// App-scoped Speak session so audio + Live Activity survive leaving the Speak UI.
@MainActor
final class SpeakSessionController: ObservableObject {
    let voice = VoiceService()

    @Published var isRunning = false
    @Published var lastReply = ""
    @Published var statusLine = "Speak bereit"
    @Published var showSpeakUI = false

    private weak var connection: ConnectionStore?
    private var isBusy = false
    private var wired = false

    func bind(connection: ConnectionStore) {
        self.connection = connection
        guard !wired else { return }
        wired = true
        voice.onAutoUtterance = { [weak self] text in
            Task { await self?.handleUtterance(text) }
        }
        voice.onSpeakFinished = { [weak self] in
            self?.resumeListening()
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
            try voice.activateBackgroundAudioSession()
            isRunning = true
            voice.sessionActive = true
            SpeakLiveActivityManager.start()
            try voice.startListening(autoEnd: true)
            statusLine = "Zuhören — Pause sendet automatisch"
            pushLiveActivity(force: true)
            HapticService.medium()
        } catch {
            isRunning = false
            voice.phase = .error(error.localizedDescription)
            statusLine = "Mikrofon-Fehler"
        }
    }

    func stop() {
        isRunning = false
        voice.sessionActive = false
        voice.stopSpeaking()
        voice.stopListening(cancel: true)
        SpeakLiveActivityManager.end()
        voice.phase = .idle
        statusLine = "Speak gestoppt"
    }

    private func resumeListening() {
        guard isRunning, connection?.isOnline == true, !isBusy else { return }
        do {
            try voice.startListening(autoEnd: true)
            statusLine = "Wieder Zuhören…"
            pushLiveActivity(force: true)
        } catch {
            statusLine = "Zuhören unterbrochen"
        }
    }

    private func handleUtterance(_ text: String) async {
        guard isRunning, !isBusy, let connection else { return }
        isBusy = true
        defer { isBusy = false }

        statusLine = "Intelligence Sync…"
        voice.phase = .processing
        pushLiveActivity(force: true)
        HapticService.send()

        let prompt = VoiceService.voiceOnlyPrompt(text)
        let reply = await connection.chat.sendAndReturnReply(prompt, modeOverride: VoiceSettings.defaultMode)

        guard isRunning else { return }

        if let reply, !reply.isEmpty {
            lastReply = reply
            if voice.autoSpeakReplies {
                statusLine = "Spoken Reply…"
                pushLiveActivity(force: true)
                voice.speak(reply)
            } else {
                voice.phase = .idle
                resumeListening()
            }
        } else {
            let msg = connection.chat.lastError ?? "Keine Antwort"
            statusLine = msg
            voice.phase = .error(msg)
            pushLiveActivity(force: true)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if isRunning { resumeListening() }
        }
    }

    func pushLiveActivity(force: Bool) {
        guard isRunning else { return }
        let phase: SpeakActivityPhase
        switch voice.phase {
        case .listening: phase = .listening
        case .processing: phase = .processing
        case .speaking: phase = .speaking
        case .error: phase = .error
        case .idle: phase = .idle
        }
        let detail: String
        switch voice.phase {
        case .listening:
            detail = voice.liveTranscript.isEmpty ? "Sprich weiter…" : voice.liveTranscript
        case .speaking:
            detail = lastReply
        case .processing:
            detail = "Nur Sprache · \(VoiceSettings.defaultMode.label)"
        case .error(let m):
            detail = m
        case .idle:
            detail = "Bereit"
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
            force: force
        )
    }
}
