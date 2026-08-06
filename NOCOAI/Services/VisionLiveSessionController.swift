import Combine
import Foundation
import UIKit

/// NOCO Vision Live — real-time camera understanding session.
@MainActor
final class VisionLiveSessionController: ObservableObject {
    @Published private(set) var hasConsent = false
    @Published private(set) var isLive = false
    @Published var intent: VisionLiveIntent = .understand
    @Published var quality: LiveScreenQuality = .auto
    @Published var autoAssist = true
    @Published private(set) var phase: LiveScreenPhase = .idle
    @Published private(set) var turns: [VisionLiveTurn] = []
    @Published private(set) var suggestions: [VisionLiveSuggestion] = []
    @Published private(set) var latestOCR = ""
    @Published private(set) var isAnalyzing = false
    @Published private(set) var statusLine = "Bereit"
    @Published private(set) var activeModelLabel = ""
    @Published private(set) var lastError: String?
    @Published private(set) var conversationId: String?
    @Published var draft = ""

    let camera = VisionLiveCameraController()
    let voice = VoiceService()

    private var apiProvider: (() -> CompanionAPI?)?
    private var lastAutoAt: Date?
    private var lastFingerprint: Int?
    private var latestJPEG: Data?
    private let consentKey = "noco.visionlive.consent.v1"

    init() {
        hasConsent = UserDefaults.standard.bool(forKey: consentKey)
        camera.setFrameHandler { [weak self] image in
            Task { @MainActor in
                await self?.handlePreviewFrame(image)
            }
        }
    }

    func bind(apiProvider: @escaping () -> CompanionAPI?) {
        self.apiProvider = apiProvider
    }

    func clearError() { lastError = nil }

    func grantConsent() {
        hasConsent = true
        UserDefaults.standard.set(true, forKey: consentKey)
        HapticService.success()
    }

    func startLive() async {
        guard hasConsent else {
            lastError = "Kamera braucht deine Zustimmung."
            return
        }
        await camera.requestAccessAndStart()
        guard !camera.permissionDenied else {
            lastError = "Kamerazugriff verweigert — bitte in den iOS-Einstellungen erlauben."
            return
        }
        isLive = true
        statusLine = "Vision Live aktiv"
        phase = .idle
        if turns.isEmpty {
            turns.append(
                VisionLiveTurn(
                    role: .system,
                    text: "NOCO Vision Live sieht mit dir. Richte die Kamera auf etwas und frag — oder lass Auto-Assistent mitdenken."
                )
            )
        }
        HapticService.open()
    }

    func stopLive() {
        camera.stop()
        voice.stopListening(cancel: true)
        isLive = false
        isAnalyzing = false
        phase = .idle
        statusLine = "Beendet"
        HapticService.soft()
    }

    private func handlePreviewFrame(_ image: UIImage) async {
        guard isLive, autoAssist, !isAnalyzing else { return }
        let now = Date()
        if let last = lastAutoAt, now.timeIntervalSince(last) < 7 { return }
        // Only auto when scene likely changed
        guard let jpeg = LiveScreenImageOptimizer.jpeg(from: image, maxSide: 960, quality: 0.7) else { return }
        let fp = jpeg.count
        if fp == lastFingerprint { return }
        lastFingerprint = fp
        lastAutoAt = now
        latestJPEG = jpeg
        await analyze(image: image, userPrompt: nil, isAuto: true)
    }

    func captureAndAsk(_ prompt: String?) async {
        guard isLive else {
            lastError = "Vision Live ist nicht aktiv."
            return
        }
        guard let image = await camera.captureStill() else {
            lastError = "Kein Kamerabild verfügbar."
            HapticService.error()
            return
        }
        await analyze(image: image, userPrompt: prompt, isAuto: false)
    }

    func startVoiceAsk() async {
        do {
            _ = await voice.requestPermissions()
            try voice.activateBackgroundAudioSession()
            try voice.startListening(autoEnd: true)
            statusLine = "Zuhören…"
            HapticService.soft()
            for _ in 0..<48 {
                if case .listening = voice.phase {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    continue
                }
                break
            }
            // Wait briefly for final transcript after auto-end
            try? await Task.sleep(nanoseconds: 350_000_000)
            let text = voice.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                statusLine = isLive ? "Vision Live aktiv" : "Bereit"
                return
            }
            draft = text
            await captureAndAsk(text)
        } catch {
            lastError = error.localizedDescription
            HapticService.error()
        }
    }

    private func analyze(image: UIImage, userPrompt: String?, isAuto: Bool) async {
        guard !isAnalyzing else { return }
        guard let companion = apiProvider?() else {
            if !isAuto {
                lastError = "Companion offline — bitte koppeln."
                HapticService.error()
            }
            return
        }
        guard let jpeg = LiveScreenImageOptimizer.jpeg(from: image) else { return }
        latestJPEG = jpeg

        isAnalyzing = true
        withPhase(.recognizing, status: "Erkennen…")
        defer { isAnalyzing = false }

        let ocr = await LiveScreenOCR.recognizeText(in: image)
        latestOCR = String(ocr.prefix(500))
        suggestions = VisionLiveSuggestion.from(ocr: ocr, intent: intent)
        withPhase(.understanding, status: "Verstehen…")

        let question = (userPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? (isAuto ? proactiveAutoPrompt(ocr: ocr) : intent.defaultPrompt)

        if !isAuto {
            turns.append(VisionLiveTurn(role: .user, text: question))
        }

        let prompt = buildPrompt(question: question, ocr: ocr)
        withPhase(.answering, status: "Antwort…")
        HapticService.rigid()

        do {
            let result = try await companion.uploadVisionImage(
                imageData: jpeg,
                filename: "visionlive.jpg",
                message: prompt,
                conversationId: conversationId,
                qualityProfile: quality.rawValue,
                ocrLength: ocr.count
            )
            if let cid = result.conversationId, !cid.isEmpty {
                conversationId = cid
            }
            var reply = result.replyText?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "Ich konnte die Szene gerade nicht sicher deuten."
            if let range = reply.range(of: "\n—\nNOCO nutzt:") {
                activeModelLabel = String(reply[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                reply = String(reply[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // Soft-skip low-value auto replies
            if isAuto, reply.count < 40 { 
                withPhase(.idle, status: "Vision Live aktiv")
                return
            }
            turns.append(VisionLiveTurn(role: .assistant, text: reply))
            withPhase(.done, status: activeModelLabel.isEmpty ? "Bereit" : activeModelLabel)
            HapticService.messageReceived()
            HapticService.success()
            try? await Task.sleep(nanoseconds: 700_000_000)
            withPhase(.idle, status: "Vision Live aktiv")
        } catch {
            if !isAuto {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                lastError = msg
                turns.append(VisionLiveTurn(role: .assistant, text: "Analyse fehlgeschlagen: \(msg)"))
                HapticService.error()
            }
            withPhase(.idle, status: "Vision Live aktiv")
        }
    }

    private func proactiveAutoPrompt(ocr: String) -> String {
        if ocr.count > 100 {
            return "Schau dir die Szene und den sichtbaren Text an. Verstehe die Situation und biete eine kurze, hilfreiche nächste Aktion an."
        }
        return "Was sehe ich hier? Verstehe die Situation und schlage eine sinnvolle Hilfe vor — nicht nur benennen."
    }

    private func buildPrompt(question: String, ocr: String) -> String {
        var parts = [intent.systemDirective]
        parts.append(
            """
            Dies ist NOCO Vision Live (Kamera, Echtzeit). Nicht wie ein Screenshot-Chat wirken: \
            verstehe Absicht, biete Hilfe an, bleib natürlich. Keine Floskeln. Auf Deutsch.
            Integration: Wenn es wie ein Bildschirm/UI aussieht, arbeite wie Live Screen (Schritte erklären).
            """
        )
        if !ocr.isEmpty {
            parts.append("OCR (lokal):\n\(String(ocr.prefix(3500)))")
        }
        parts.append("Nutzer:\n\(question)")
        return parts.joined(separator: "\n\n")
    }

    private func withPhase(_ p: LiveScreenPhase, status: String) {
        phase = p
        statusLine = status
    }
}
