import Combine
import Foundation
import SwiftUI
import UIKit

/// Orchestrates consent → intelligent capture → OCR → vision → contextual reply.
/// Frames are NOT streamed at 60fps — only significant changes or user questions trigger analysis.
@MainActor
final class LiveScreenSessionController: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var hasConsent = false
    @Published var mode: LiveScreenMode = .help
    @Published var quality: LiveScreenQuality = .auto
    @Published private(set) var phase: LiveScreenPhase = .idle
    @Published private(set) var turns: [LiveScreenTurn] = []
    @Published private(set) var latestPreview: UIImage?
    @Published private(set) var latestOCRPreview: String = ""
    @Published private(set) var suggestedActions: [LiveScreenSuggestedAction] = []
    @Published private(set) var activeModelLabel: String = ""
    @Published private(set) var isAnalyzing = false
    @Published private(set) var statusLine = "Bereit"
    @Published private(set) var lastError: String?
    @Published private(set) var conversationId: String?
    @Published private(set) var captureKind: LiveScreenCaptureKind?
    @Published var autoAssistEnabled = true
    /// When Speak is talking / processing — never upload a new vision frame.
    @Published var suppressAutoVision = false
    @Published private(set) var sessionSummary = ""
    @Published private(set) var contextNotes: [LiveScreenContextNote] = []
    @Published var showEndSessionSheet = false
    @Published private(set) var broadcastWaiting = true

    /// In-memory only — frames are never written to disk by default (privacy).
    private(set) var latestFrame: LiveScreenFrame?
    private var replayCapture: LiveScreenInAppReplayCapture?
    private var broadcastCapture: LiveScreenBroadcastCapture?
    private var lastAutoAnalyzeAt: Date?
    private var lastPerceptualHash: UInt64?
    private var lastOCRFingerprint = ""
    private var didInitialSummary = false
    private var pendingUserPrompt: String?
    private var apiProvider: (() -> CompanionAPI?)?
    private var speakBusyProvider: (() -> Bool)?

    private let consentKey = "noco.livescreen.consent.v1"
    private let savedContextKey = "noco.livescreen.savedContext.v1"

    init() {
        hasConsent = UserDefaults.standard.bool(forKey: consentKey)
        restorePersistedContextIfNeeded()
    }

    func bind(apiProvider: @escaping () -> CompanionAPI?, speakBusy: (() -> Bool)? = nil) {
        self.apiProvider = apiProvider
        self.speakBusyProvider = speakBusy
    }

    func clearError() {
        lastError = nil
    }

    /// Latest JPEG for Speak / handoff (no disk).
    var latestJPEG: Data? { latestFrame?.jpegData }

    var contextBriefing: String {
        var parts: [String] = []
        if !sessionSummary.isEmpty {
            parts.append("Aktuelle Übersicht:\n\(sessionSummary)")
        }
        let recent = contextNotes.suffix(6).map { "• \($0.text)" }.joined(separator: "\n")
        if !recent.isEmpty {
            parts.append("Kontextnotiz:\n\(recent)")
        }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Consent & lifecycle

    func grantConsent() {
        hasConsent = true
        UserDefaults.standard.set(true, forKey: consentKey)
        HapticService.success()
    }

    func revokeConsentAndStop() {
        hasConsent = false
        UserDefaults.standard.set(false, forKey: consentKey)
        stopSession(offerSave: false)
    }

    func startSession() throws {
        guard hasConsent else { throw LiveScreenError.notConsented }
        isActive = true
        lastError = nil
        didInitialSummary = false
        broadcastWaiting = true
        statusLine = "Live Screen aktiv — Bildschirm teilen"
        withAnimation(.easeInOut(duration: 0.35)) { phase = .idle }
        if turns.isEmpty {
            turns.append(
                LiveScreenTurn(
                    role: .system,
                    text: "Tippe den roten Übertragen-Button und wähle „NOCO Live Screen“. NOCO analysiert nur bei relevanten Änderungen oder wenn du fragst — kein Dauer-Streaming."
                )
            )
        }
        HapticService.open()
        Task { await startBroadcastCapture() }
    }

    /// Soft stop — optionally keep / discard session context.
    func requestStopSession() {
        guard isActive else { return }
        if !sessionSummary.isEmpty || !contextNotes.isEmpty {
            showEndSessionSheet = true
        } else {
            stopSession(offerSave: false)
        }
    }

    func stopSession(offerSave: Bool = true, keepContext: Bool = false) {
        if offerSave, (!sessionSummary.isEmpty || !contextNotes.isEmpty), keepContext == false, showEndSessionSheet == false {
            showEndSessionSheet = true
            return
        }
        replayCapture?.stop()
        replayCapture = nil
        broadcastCapture?.stop()
        broadcastCapture = nil
        SharedBroadcastFrameStore.clear()
        isActive = false
        isAnalyzing = false
        suppressAutoVision = false
        phase = .idle
        latestFrame = nil
        latestPreview = nil
        latestOCRPreview = ""
        suggestedActions = []
        activeModelLabel = ""
        captureKind = nil
        broadcastWaiting = true
        pendingUserPrompt = nil
        lastPerceptualHash = nil
        lastOCRFingerprint = ""
        lastAutoAnalyzeAt = nil
        if !keepContext {
            sessionSummary = ""
            contextNotes = []
            conversationId = nil
            clearPersistedContext()
        }
        statusLine = keepContext ? "Beendet · Kontext gespeichert" : "Beendet"
        showEndSessionSheet = false
        HapticService.soft()
    }

    func saveContextAndStop() {
        persistContext()
        stopSession(offerSave: false, keepContext: true)
    }

    func discardContextAndStop() {
        clearPersistedContext()
        sessionSummary = ""
        contextNotes = []
        conversationId = nil
        stopSession(offerSave: false, keepContext: false)
    }

    func clearConversation() {
        turns.removeAll()
        conversationId = nil
        lastError = nil
        sessionSummary = ""
        contextNotes = []
        didInitialSummary = false
        clearPersistedContext()
    }

    // MARK: - Ingest frames

    /// Preview-only update (no OCR / no upload) — used for live thumbnail.
    func updatePreview(_ image: UIImage, source: LiveScreenCaptureKind) {
        guard isActive else { return }
        latestPreview = image
        captureKind = source
        if source == .broadcastExtension {
            broadcastWaiting = false
            if statusLine.contains("Warte") || statusLine.contains("Übertragung") {
                statusLine = "👁 Beobachte Bildschirm"
            }
        }
    }

    func ingest(
        image: UIImage,
        source: LiveScreenCaptureKind,
        autoAnalyze: Bool = false,
        force: Bool = false,
        userPrompt: String? = nil
    ) async {
        guard isActive else { return }
        guard let jpeg = LiveScreenImageOptimizer.jpeg(from: image) else {
            lastError = LiveScreenError.processing.errorDescription
            return
        }

        let hash = LiveScreenSceneDiff.perceptualHash(of: image)
        let sceneChanged = LiveScreenSceneDiff.isSignificant(previous: lastPerceptualHash, new: hash)
        if !force, !sceneChanged, source == .broadcastExtension || source == .inAppReplay {
            updatePreview(image, source: source)
            return
        }

        statusLine = "👁 Erfasse Bildschirm"
        withAnimation(.easeInOut(duration: 0.35)) { phase = .recognizing }
        let ocr = await LiveScreenOCR.recognizeText(in: image)
        let ocrDelta = LiveScreenSceneDiff.ocrChanged(lastOCRFingerprint, ocr)

        // Skip quiet broadcasts that barely changed visually and in text
        if !force, !autoAnalyze, source == .broadcastExtension,
           lastPerceptualHash != nil, !ocrDelta,
           LiveScreenSceneDiff.hamming(lastPerceptualHash ?? 0, hash) < 14 {
            updatePreview(image, source: source)
            withAnimation(.easeInOut(duration: 0.25)) { phase = .idle }
            return
        }

        lastPerceptualHash = hash
        lastOCRFingerprint = ocr

        let frame = LiveScreenFrame(
            jpegData: jpeg,
            ocrText: ocr,
            capturedAt: Date(),
            source: source,
            width: Int(image.size.width),
            height: Int(image.size.height),
            perceptualHash: hash
        )
        latestFrame = frame
        latestPreview = image
        latestOCRPreview = String(ocr.prefix(400))
        captureKind = source
        suggestedActions = LiveScreenSuggestedAction.from(ocr: ocr, mode: mode)
        appendContext(.ocr, text: String(ocr.prefix(280)))
        if let app = Self.guessAppHint(from: ocr) {
            appendContext(.appHint, text: "Anwendungshinweis: \(app)")
        }
        statusLine = ocr.isEmpty ? "Bild bereit" : "Text erkannt · bereit"
        withAnimation(.easeInOut(duration: 0.35)) { phase = .idle }
        HapticService.soft()

        let shouldAnalyze: Bool
        if force || userPrompt != nil {
            shouldAnalyze = true
        } else if autoAnalyze {
            shouldAnalyze = canAutoAnalyze()
        } else {
            shouldAnalyze = false
        }

        if shouldAnalyze {
            await analyze(userPrompt: userPrompt, isInitialSummary: !didInitialSummary && userPrompt == nil)
        }
    }

    func ingestClipboardIfPossible() async -> Bool {
        guard isActive else {
            lastError = LiveScreenError.notActive.errorDescription
            return false
        }
        guard let image = UIPasteboard.general.image else {
            lastError = "Keine Bilddaten in der Zwischenablage."
            HapticService.error()
            return false
        }
        await ingest(image: image, source: .clipboard, autoAnalyze: true, force: true)
        return true
    }

    func startInAppCapture() async {
        guard isActive else { return }
        broadcastCapture?.stop()
        broadcastCapture = nil
        let capture = LiveScreenInAppReplayCapture()
        capture.onFrame = { [weak self] image in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                self.updatePreview(image, source: .inAppReplay)
                guard self.autoAssistEnabled, self.canAutoAnalyze() else { return }
                let now = Date()
                if let last = self.lastAutoAnalyzeAt, now.timeIntervalSince(last) < 10 { return }
                self.lastAutoAnalyzeAt = now
                await self.ingest(image: image, source: .inAppReplay, autoAnalyze: true)
            }
        }
        do {
            try await capture.prepare()
            replayCapture = capture
            statusLine = "In-App-Aufnahme (nur NOCO-Fenster)"
            HapticService.success()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            HapticService.error()
        }
    }

    /// Start listening for system Broadcast frames (Control Center / picker).
    func startBroadcastCapture() async {
        guard isActive else { return }
        replayCapture?.stop()
        replayCapture = nil
        let capture = LiveScreenBroadcastCapture()
        capture.onWaitingStatus = { [weak self] line in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                if self.captureKind != .broadcastExtension || self.latestPreview == nil {
                    self.broadcastWaiting = true
                    self.statusLine = line
                }
            }
        }
        capture.onFrame = { [weak self] image in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                self.broadcastWaiting = false
                self.updatePreview(image, source: .broadcastExtension)

                // Always refresh preview; only analyze on meaningful change + policy
                guard self.canAutoAnalyze() else { return }
                let hash = LiveScreenSceneDiff.perceptualHash(of: image)
                let changed = LiveScreenSceneDiff.isSignificant(previous: self.lastPerceptualHash, new: hash, threshold: 12)
                let now = Date()
                let throttle: TimeInterval = self.autoAssistEnabled ? 6.0 : 20.0
                if let last = self.lastAutoAnalyzeAt, now.timeIntervalSince(last) < throttle { return }

                // First frame → overview. Later → only on scene change when Auto on.
                let isFirst = !self.didInitialSummary
                if isFirst || (self.autoAssistEnabled && changed) {
                    self.lastAutoAnalyzeAt = now
                    await self.ingest(
                        image: image,
                        source: .broadcastExtension,
                        autoAnalyze: true,
                        force: isFirst
                    )
                }
            }
        }
        do {
            try await capture.prepare()
            broadcastCapture = capture
            statusLine = "Warte auf Bildschirmübertragung…"
            HapticService.success()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            HapticService.error()
        }
    }

    func stopBroadcastCapture() {
        broadcastCapture?.stop()
        broadcastCapture = nil
        if captureKind == .broadcastExtension {
            captureKind = nil
            statusLine = "Übertragung gestoppt"
        }
    }

    func stopInAppCapture() {
        replayCapture?.stop()
        replayCapture = nil
        if captureKind == .inAppReplay {
            statusLine = "Aufnahme gestoppt"
        }
    }

    func captureCurrentInAppFrame() async {
        guard let image = replayCapture?.currentFrame() ?? latestPreview else {
            lastError = LiveScreenError.noFrame.errorDescription
            return
        }
        await ingest(image: image, source: captureKind ?? .inAppReplay, autoAnalyze: true, force: true)
    }

    /// Speak / user question: grab current frame and analyze with the question.
    func analyzeWithQuestion(_ question: String) async -> String? {
        if let image = latestPreview ?? replayCapture?.currentFrame() {
            await ingest(
                image: image,
                source: captureKind ?? .broadcastExtension,
                autoAnalyze: false,
                force: true,
                userPrompt: question
            )
        } else {
            await analyze(userPrompt: question)
        }
        return turns.last(where: { $0.role == .assistant })?.text
    }

    // MARK: - Analyze pipeline

    func analyze(userPrompt: String?, api: CompanionAPI? = nil, isInitialSummary: Bool = false) async {
        guard isActive else {
            lastError = LiveScreenError.notActive.errorDescription
            return
        }
        guard !isAnalyzing else {
            pendingUserPrompt = userPrompt
            return
        }
        if speakBusyProvider?() == true || suppressAutoVision {
            // Queue for after Speak finishes
            pendingUserPrompt = userPrompt ?? pendingUserPrompt
            statusLine = "Warte bis die Antwort zu Ende ist…"
            return
        }
        guard let frame = latestFrame else {
            if let preview = latestPreview {
                await ingest(
                    image: preview,
                    source: captureKind ?? .broadcastExtension,
                    autoAnalyze: false,
                    force: true,
                    userPrompt: userPrompt
                )
                return
            }
            lastError = LiveScreenError.permissionNeeded.errorDescription
            HapticService.error()
            return
        }

        guard let companion = api ?? apiProvider?() else {
            lastError = LiveScreenError.offline.errorDescription
            HapticService.error()
            return
        }

        let resolvedQuality: LiveScreenQuality = {
            if quality == .auto {
                return LiveScreenQuality.recommend(ocr: frame.ocrText, userPrompt: userPrompt)
            }
            return quality
        }()

        let prompt = buildPrompt(
            userPrompt: userPrompt,
            ocr: frame.ocrText,
            isInitialSummary: isInitialSummary
        )
        let thumb = LiveScreenImageOptimizer.thumbnail(from: frame.jpegData)
        let userLabel: String
        if isInitialSummary {
            userLabel = "Übersicht erstellen"
        } else if let userPrompt, !userPrompt.isEmpty {
            userLabel = userPrompt
        } else {
            userLabel = mode.defaultUserPrompt
        }
        turns.append(LiveScreenTurn(role: .user, text: userLabel, thumbnailJPEG: thumb))
        if let userPrompt, !userPrompt.isEmpty {
            appendContext(.userQ, text: userPrompt)
        }

        isAnalyzing = true
        statusLine = "🧠 Analysiere"
        withAnimation(.easeInOut(duration: 0.35)) { phase = .understanding }
        lastError = nil
        HapticService.prepare()
        HapticService.rigid()
        defer {
            isAnalyzing = false
            if let pending = pendingUserPrompt {
                pendingUserPrompt = nil
                Task { await self.analyze(userPrompt: pending) }
            }
        }

        do {
            withAnimation(.easeInOut(duration: 0.35)) { phase = .answering }
            statusLine = "🎙 Antwort wird vorbereitet"
            let result = try await companion.uploadVisionImage(
                imageData: frame.jpegData,
                filename: "livescreen.jpg",
                message: prompt,
                conversationId: conversationId,
                qualityProfile: resolvedQuality.rawValue,
                ocrLength: frame.ocrText.count,
                source: "livescreen"
            )
            if let cid = result.conversationId, !cid.isEmpty {
                conversationId = cid
            }
            var reply = result.replyText?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "Keine Antwort von der Bildanalyse."
            if let range = reply.range(of: "\n—\nNOCO nutzt:") {
                activeModelLabel = String(reply[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                reply = String(reply[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            turns.append(LiveScreenTurn(role: .assistant, text: reply))
            appendContext(.insight, text: String(reply.prefix(400)))
            if isInitialSummary || sessionSummary.isEmpty {
                sessionSummary = reply
                didInitialSummary = true
                appendContext(.summary, text: String(reply.prefix(500)))
            }
            statusLine = activeModelLabel.isEmpty ? "✅ Fertig" : "✅ Fertig · \(activeModelLabel)"
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { phase = .done }
            HapticService.messageReceived()
            HapticService.success()
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(.easeInOut(duration: 0.4)) { phase = .idle }
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastError = msg
            turns.append(LiveScreenTurn(role: .assistant, text: "Analyse fehlgeschlagen: \(msg)"))
            statusLine = "Fehler"
            withAnimation(.easeInOut(duration: 0.3)) { phase = .idle }
            HapticService.error()
        }
    }

    /// Flush queued analysis after Speak finishes speaking.
    func resumeQueuedAnalysisIfNeeded() {
        guard isActive, !isAnalyzing, !suppressAutoVision else { return }
        guard speakBusyProvider?() != true else { return }
        if let pending = pendingUserPrompt {
            pendingUserPrompt = nil
            Task { await analyze(userPrompt: pending) }
        }
    }

    // MARK: - Prompt & context

    private func buildPrompt(userPrompt: String?, ocr: String, isInitialSummary: Bool) -> String {
        var parts: [String] = [mode.systemDirective]
        parts.append(
            """
            Dies ist eine Live-Screen-Sitzung (kein einmaliger Screenshot-Chat). \
            Verstehe die Situation und antworte so, als säßest du neben dem Nutzer. \
            Du kannst den Bildschirm sehen. Sage niemals, dass du keine Bilder beschreiben kannst. \
            Keine Floskeln. Keine Meta-Kommentare über KI.
            """
        )
        if !contextBriefing.isEmpty {
            parts.append("Bisheriger Sitzungskontext:\n\(contextBriefing)")
        }
        if !ocr.isEmpty {
            let clipped = String(ocr.prefix(3500))
            parts.append("OCR-Text vom Bildschirm (lokal erkannt):\n\(clipped)")
        }
        if isInitialSummary {
            parts.append(
                """
                Erstelle jetzt eine kurze Übersicht im Format:

                Ich sehe aktuell:
                • geöffnete Anwendung: …
                • wichtige Elemente: …
                • mögliche Aktionen: …

                Maximal 6 Bullet-Punkte, klar und hilfreich auf Deutsch.
                """
            )
        } else {
            let question = (userPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? mode.defaultUserPrompt
            parts.append("Nutzerfrage:\n\(question)")
        }
        return parts.joined(separator: "\n\n")
    }

    private func canAutoAnalyze() -> Bool {
        guard autoAssistEnabled else { return !didInitialSummary }
        if suppressAutoVision { return false }
        if isAnalyzing { return false }
        if speakBusyProvider?() == true { return false }
        return true
    }

    private func appendContext(_ kind: LiveScreenContextNote.Kind, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let last = contextNotes.last, last.kind == kind, last.text == trimmed { return }
        contextNotes.append(LiveScreenContextNote(kind: kind, text: trimmed))
        if contextNotes.count > 40 {
            contextNotes = Array(contextNotes.suffix(40))
        }
    }

    private static func guessAppHint(from ocr: String) -> String? {
        let lines = ocr.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first, first.count >= 2, first.count <= 48 else { return nil }
        // Skip pure URLs / status bars
        if first.lowercased().hasPrefix("http") { return nil }
        return first
    }

    private func persistContext() {
        let payload = LiveScreenPersistedContext(
            savedAt: Date(),
            summary: sessionSummary,
            notes: Array(contextNotes.suffix(24)),
            conversationId: conversationId
        )
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: savedContextKey)
        }
    }

    private func clearPersistedContext() {
        UserDefaults.standard.removeObject(forKey: savedContextKey)
    }

    private func restorePersistedContextIfNeeded() {
        guard let data = UserDefaults.standard.data(forKey: savedContextKey),
              let payload = try? JSONDecoder().decode(LiveScreenPersistedContext.self, from: data) else { return }
        // Keep at most 24h
        guard Date().timeIntervalSince(payload.savedAt) < 86_400 else {
            clearPersistedContext()
            return
        }
        sessionSummary = payload.summary
        contextNotes = payload.notes
        conversationId = payload.conversationId
        if !payload.summary.isEmpty {
            turns.append(
                LiveScreenTurn(
                    role: .system,
                    text: "Gespeicherter Kontext geladen:\n\(payload.summary)"
                )
            )
        }
    }
}
