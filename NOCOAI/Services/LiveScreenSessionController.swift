import Combine
import Foundation
import UIKit

/// Orchestrates consent → capture → OCR → vision → contextual reply.
@MainActor
final class LiveScreenSessionController: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var hasConsent = false
    @Published var mode: LiveScreenMode = .help
    @Published private(set) var turns: [LiveScreenTurn] = []
    @Published private(set) var latestPreview: UIImage?
    @Published private(set) var latestOCRPreview: String = ""
    @Published private(set) var isAnalyzing = false
    @Published private(set) var statusLine = "Bereit"
    @Published private(set) var lastError: String?
    @Published private(set) var conversationId: String?
    @Published private(set) var captureKind: LiveScreenCaptureKind?
    @Published var autoAssistEnabled = true

    /// In-memory only — frames are never written to disk by default (privacy).
    private var latestFrame: LiveScreenFrame?
    private var replayCapture: LiveScreenInAppReplayCapture?
    private var lastAutoAnalyzeAt: Date?
    private var lastFrameFingerprint: Int?
    private var apiProvider: (() -> CompanionAPI?)?

    private let consentKey = "noco.livescreen.consent.v1"

    init() {
        hasConsent = UserDefaults.standard.bool(forKey: consentKey)
    }

    func bind(apiProvider: @escaping () -> CompanionAPI?) {
        self.apiProvider = apiProvider
    }

    func clearError() {
        lastError = nil
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
        stopSession()
    }

    func startSession() throws {
        guard hasConsent else { throw LiveScreenError.notConsented }
        isActive = true
        lastError = nil
        statusLine = "Live Screen aktiv"
        if turns.isEmpty {
            turns.append(
                LiveScreenTurn(
                    role: .system,
                    text: "Live Screen ist aktiv. Teile einen Screenshot, füge ein Bild aus der Zwischenablage ein oder starte die In-App-Aufnahme. NOCO analysiert den sichtbaren Kontext."
                )
            )
        }
        HapticService.open()
    }

    func stopSession() {
        replayCapture?.stop()
        replayCapture = nil
        isActive = false
        isAnalyzing = false
        latestFrame = nil
        latestPreview = nil
        latestOCRPreview = ""
        captureKind = nil
        statusLine = "Beendet"
        HapticService.soft()
    }

    func clearConversation() {
        turns.removeAll()
        conversationId = nil
        lastError = nil
    }

    // MARK: - Ingest frames

    func ingest(image: UIImage, source: LiveScreenCaptureKind, autoAnalyze: Bool = false) async {
        guard isActive else { return }
        guard let jpeg = LiveScreenImageOptimizer.jpeg(from: image) else {
            lastError = LiveScreenError.processing.errorDescription
            return
        }

        let fingerprint = jpeg.count ^ Int(image.size.width) ^ Int(image.size.height)
        if fingerprint == lastFrameFingerprint, source == .inAppReplay {
            return
        }
        lastFrameFingerprint = fingerprint

        statusLine = "OCR…"
        let ocr = await LiveScreenOCR.recognizeText(in: image)
        let frame = LiveScreenFrame(
            jpegData: jpeg,
            ocrText: ocr,
            capturedAt: Date(),
            source: source,
            width: Int(image.size.width),
            height: Int(image.size.height)
        )
        latestFrame = frame
        latestPreview = image
        latestOCRPreview = String(ocr.prefix(400))
        captureKind = source
        statusLine = ocr.isEmpty ? "Bild bereit" : "Text erkannt · bereit"
        HapticService.soft()

        if autoAnalyze || (autoAssistEnabled && mode == .assist && source != .inAppReplay) {
            await analyze(userPrompt: nil)
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
        await ingest(image: image, source: .clipboard, autoAnalyze: true)
        return true
    }

    func startInAppCapture() async {
        guard isActive else { return }
        let capture = LiveScreenInAppReplayCapture()
        capture.onFrame = { [weak self] image in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                // Keep preview fresh; analyze only on demand or throttled assist
                self.latestPreview = image
                self.captureKind = .inAppReplay
                if self.autoAssistEnabled, self.mode == .assist {
                    let now = Date()
                    if let last = self.lastAutoAnalyzeAt, now.timeIntervalSince(last) < 8 { return }
                    self.lastAutoAnalyzeAt = now
                    await self.ingest(image: image, source: .inAppReplay, autoAnalyze: true)
                }
            }
        }
        do {
            try await capture.prepare()
            replayCapture = capture
            statusLine = "In-App-Aufnahme läuft"
            HapticService.success()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            HapticService.error()
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
        await ingest(image: image, source: .inAppReplay, autoAnalyze: true)
    }

    // MARK: - Analyze pipeline

    func analyze(userPrompt: String?, api: CompanionAPI? = nil) async {
        guard isActive else {
            lastError = LiveScreenError.notActive.errorDescription
            return
        }
        guard !isAnalyzing else {
            lastError = LiveScreenError.processing.errorDescription
            return
        }
        guard let frame = latestFrame else {
            lastError = LiveScreenError.noFrame.errorDescription
            HapticService.error()
            return
        }

        guard let companion = api ?? apiProvider?() else {
            lastError = LiveScreenError.offline.errorDescription
            HapticService.error()
            return
        }

        let prompt = buildPrompt(userPrompt: userPrompt, ocr: frame.ocrText)
        let thumb = LiveScreenImageOptimizer.thumbnail(from: frame.jpegData)
        turns.append(LiveScreenTurn(role: .user, text: userPrompt?.isEmpty == false ? userPrompt! : mode.defaultUserPrompt, thumbnailJPEG: thumb))

        isAnalyzing = true
        statusLine = "Vision + Kontext…"
        lastError = nil
        HapticService.prepare()
        HapticService.rigid()
        defer {
            isAnalyzing = false
        }

        do {
            let result = try await companion.uploadVisionImage(
                imageData: frame.jpegData,
                filename: "livescreen.jpg",
                message: prompt,
                conversationId: conversationId
            )
            if let cid = result.conversationId, !cid.isEmpty {
                conversationId = cid
            }
            let reply = result.replyText?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "Keine Antwort von der Bildanalyse."
            turns.append(LiveScreenTurn(role: .assistant, text: reply))
            statusLine = "Bereit"
            HapticService.messageReceived()
            HapticService.success()
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastError = msg
            turns.append(LiveScreenTurn(role: .assistant, text: "Analyse fehlgeschlagen: \(msg)"))
            statusLine = "Fehler"
            HapticService.error()
        }
    }

    private func buildPrompt(userPrompt: String?, ocr: String) -> String {
        var parts: [String] = [mode.systemDirective]
        parts.append(
            """
            Dies ist eine Live-Screen-Sitzung (kein einmaliger Screenshot-Chat). \
            Verstehe die Situation und antworte so, als säßest du neben dem Nutzer. \
            Keine Floskeln. Keine Meta-Kommentare über KI.
            """
        )
        if !ocr.isEmpty {
            let clipped = String(ocr.prefix(3500))
            parts.append("OCR-Text vom Bildschirm (lokal erkannt):\n\(clipped)")
        }
        let question = (userPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? mode.defaultUserPrompt
        parts.append("Nutzerfrage:\n\(question)")
        return parts.joined(separator: "\n\n")
    }
}
