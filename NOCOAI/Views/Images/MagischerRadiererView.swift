import PhotosUI
import SwiftUI
import UIKit

/// Magischer AI-Radierer: Foto → bemalen → Standard „Entfernen“ oder eigene Anweisung → nur Maske ändert sich.
struct MagischerRadiererView: View {
    enum Preset: String, CaseIterable, Identifiable {
        case erase
        case replace
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .erase: return "Entfernen"
            case .replace: return "Ersetzen"
            case .custom: return "Eigenes"
            }
        }

        var systemImage: String {
            switch self {
            case .erase: return "eraser.fill"
            case .replace: return "arrow.triangle.2.circlepath"
            case .custom: return "pencil.line"
            }
        }

        /// User-facing instruction (also drives SD prompt).
        var defaultText: String {
            switch self {
            case .erase: return "Entferne den markierten Bereich und fülle natürlich mit dem Hintergrund."
            case .replace: return "Ersetze den markierten Bereich durch: "
            case .custom: return ""
            }
        }
    }

    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme

    @State private var photoItem: PhotosPickerItem?
    @State private var sourceImage: UIImage?
    @State private var brushSize: CGFloat = 36
    @State private var selectTool: MaskSelectTool = .paint
    @State private var preset: Preset = .erase
    @State private var instruction = Preset.erase.defaultText
    @State private var isWorking = false
    @State private var workProgress: Double = 0
    @State private var status = "Foto wählen · bemalen oder Antippen"
    @State private var resultImage: UIImage?
    @State private var canvas = MaskCanvasController()
    @State private var showLibrary = false
    @State private var revealResult = false
    @State private var maskPulse = false
    @State private var isPainting = false
    @State private var maskReady = false
    @State private var errorAlert: String?
    @State private var isAutoSelecting = false
    @FocusState private var promptFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                canvasCard
                    .padding(.horizontal, 16)
                    .frame(minHeight: 340)

                toolBar
                    .padding(.horizontal, 16)

                if preset == .custom || preset == .replace {
                    promptCard
                        .padding(.horizontal, 16)
                }

                if let resultImage {
                    resultCard(resultImage)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 16)
        }
        .nocoBackground()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionButtons
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 10)
                .background {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea(edges: .bottom)
                        .shadow(color: .black.opacity(0.12), radius: 12, y: -4)
                }
        }
        .overlay {
            if isWorking {
                MagicEraserTheater(progress: workProgress, status: status)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: isWorking)
        .navigationTitle("Magischer Radierer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { connection.hideMainTabBar = true }
        .onDisappear { connection.hideMainTabBar = false }
        .photosPicker(isPresented: $showLibrary, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .alert("Hinweis", isPresented: Binding(
            get: { errorAlert != nil },
            set: { presented in
                if !presented {
                    errorAlert = nil
                    if status.hasPrefix("Fehler:") {
                        status = maskReady
                            ? "Bereit — Entfernen tippen"
                            : "Bereich bemalen"
                    }
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorAlert ?? "")
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                maskPulse = true
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(status)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NOCOAITheme.accent)
                .contentTransition(.opacity)
            Text("Bemalen oder antippen — Auto erkennt die Kontur.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canvasCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)

            if let sourceImage {
                MaskPaintCanvas(
                    image: sourceImage,
                    controller: canvas,
                    brushSize: brushSize,
                    tool: selectTool,
                    onPaintingChange: { painting in
                        isPainting = painting
                    },
                    onMaskChanged: { painted in
                        maskReady = painted
                        if painted, selectTool == .auto {
                            status = "Objekt erkannt — Entfernen tippen"
                        }
                    },
                    onAutoBusy: { busy in
                        isAutoSelecting = busy
                        if busy { status = "Erkenne Kontur…" }
                    }
                )
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(8)
                    .overlay {
                        if maskReady {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(
                                    AngularGradient(
                                        colors: rainbowColors.map { $0.opacity(maskPulse ? 0.85 : 0.45) },
                                        center: .center
                                    ),
                                    lineWidth: 2.5
                                )
                                .padding(8)
                                .allowsHitTesting(false)
                        }
                    }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(NOCOAITheme.accent)
                    Text("Foto wählen")
                        .font(.subheadline.weight(.semibold))
                    Text("Dann den Bereich bemalen, den du ändern willst.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        HapticService.open()
                        showLibrary = true
                    } label: {
                        Label("Galerie", systemImage: "photo.on.rectangle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(36)
            }
        }
        .frame(minHeight: 340)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(NOCOAITheme.glowPrimary.opacity(0.28), lineWidth: 1)
        )
    }

    private var toolBar: some View {
        VStack(spacing: 12) {
            Picker("Aktion", selection: $preset) {
                ForEach(Preset.allCases) { p in
                    Text(p.title).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: preset) { _, p in
                HapticService.selection()
                if p != .custom {
                    instruction = p.defaultText
                } else if instruction == Preset.erase.defaultText || instruction == Preset.replace.defaultText {
                    instruction = ""
                }
                if p == .custom || p == .replace { promptFocused = true }
            }

            Picker("Auswahl", selection: $selectTool) {
                ForEach(MaskSelectTool.allCases) { t in
                    Label(t.title, systemImage: t.systemImage).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectTool) { _, tool in
                HapticService.selection()
                status = tool == .auto
                    ? "Objekt antippen — Kontur wird erkannt"
                    : "Bereich bemalen"
            }

            HStack(spacing: 12) {
                Image(systemName: selectTool == .auto ? "circle.dashed" : "paintbrush.pointed.fill")
                    .foregroundStyle(NOCOAITheme.accent)
                Slider(value: $brushSize, in: 14...64)
                Text("\(Int(brushSize))")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
            }
            Text(selectTool == .auto ? "Kreis = Auto-Radius" : "Pinselgröße")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button {
                    HapticService.light()
                    showLibrary = true
                } label: {
                    Label("Foto", systemImage: "photo")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.bordered)

                Button {
                    HapticService.soft()
                    canvas.clear()
                    maskReady = false
                    status = selectTool == .auto ? "Objekt antippen" : "Bereich bemalen"
                } label: {
                    Label("Maske löschen", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.bordered)
                .disabled(sourceImage == nil || isWorking || isAutoSelecting)
            }
        }
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preset == .replace ? "Ersetzen durch…" : "Eigene Anweisung")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(
                preset == .replace
                    ? "z. B. blauer Himmel…"
                    : "z. B. entferne das Auto…",
                text: $instruction,
                axis: .vertical
            )
            .lineLimit(2...4)
            .focused($promptFocused)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
        }
    }

    private var actionButtons: some View {
        Button {
            Task { await runEraser() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .symbolEffect(.bounce, value: isWorking)
                Text(isWorking ? "Läuft…" : (preset == .erase ? "Entfernen" : "Anwenden"))
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                LinearGradient(
                    colors: rainbowColors.dropLast(),
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .foregroundStyle(.white)
            .shadow(color: Color(red: 0.45, green: 0.4, blue: 1).opacity(0.4), radius: 14, y: 5)
        }
        .disabled(isWorking || sourceImage == nil || effectivePrompt.isEmpty || !maskReady)
        .opacity(sourceImage == nil || !maskReady ? 0.5 : 1)
    }

    private var effectivePrompt: String {
        instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var rainbowColors: [Color] {
        [
            Color(red: 0.35, green: 0.75, blue: 1),
            Color(red: 0.45, green: 0.5, blue: 1),
            Color(red: 0.75, green: 0.4, blue: 0.95),
            Color(red: 0.95, green: 0.45, blue: 0.7),
            Color(red: 0.4, green: 0.9, blue: 0.85)
        ]
    }

    private func resultCard(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ergebnis")
                .font(.subheadline.weight(.semibold))
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: NOCOAITheme.glowPrimary.opacity(0.28), radius: 14)
                .scaleEffect(revealResult ? 1 : 0.94)
                .opacity(revealResult ? 1 : 0)

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) {
                        sourceImage = image
                        resultImage = nil
                        revealResult = false
                        maskReady = false
                        canvas.clear()
                        status = "Weiter bearbeiten — neu bemalen"
                    }
                    HapticService.open()
                } label: {
                    Label("Weiter bearbeiten", systemImage: "paintbrush.pointed")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.bordered)

                Button {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    HapticService.success()
                    status = "In Fotos gespeichert"
                } label: {
                    Label("Speichern", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        if let data = await ChatPhotoLoader.loadJPEG(from: item),
           let ui = UIImage(data: data) {
            sourceImage = ui
            resultImage = nil
            revealResult = false
            maskReady = false
            canvas.clear()
            status = "Bereich bemalen"
            HapticService.success()
        } else {
            presentError("Foto konnte nicht geladen werden")
            HapticService.error()
        }
        photoItem = nil
    }

    private func presentError(_ message: String) {
        let cleaned = friendlyEraserError(message)
        status = "Fehler: \(cleaned)"
        errorAlert = cleaned
    }

    private func friendlyEraserError(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("error 64") || lower.contains("host is down") || lower.contains("nicht erreichbar") {
            return "PC nicht erreichbar (Netzwerk). Companion starten, gleiches WLAN, Port 4747."
        }
        if lower.contains("stable diffusion") || lower.contains("nicht bereit") || lower.contains("bilder-engine") {
            return "Bilder-Engine noch nicht bereit — Entfernen nochmal tippen, dann startet sie automatisch (30–90s beim ersten Mal)."
        }
        if lower.contains("unbekannte") || lower.contains("route") || lower.contains("404") {
            return "Inpaint-Route fehlt — NOCO AI X Companion neu starten."
        }
        return raw
            .replacingOccurrences(of: "Fehler: ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runEraser() async {
        guard let sourceImage else {
            presentError("Kein Foto")
            return
        }
        guard connection.isOnline else {
            presentError("Nicht mit PC verbunden")
            return
        }
        let prompt = effectivePrompt
        guard !prompt.isEmpty else { return }

        guard maskReady, canvas.hasPaint,
              canvas.exportMaskPNG(matching: sourceImage) != nil else {
            presentError("Bitte zuerst einen Bereich bemalen")
            HapticService.warning()
            return
        }

        let working = sourceImage.resizedToFit(maxSide: 768)
        guard let jpeg = working.jpegData(compressionQuality: 0.9),
              let maskForSD = canvas.exportMaskPNG(matching: working) else {
            presentError("Maske konnte nicht exportiert werden — nochmal bemalen")
            return
        }

        isWorking = true
        workProgress = 0.08
        promptFocused = false
        status = "Nur Maske wird bearbeitet…"
        HapticService.medium()

        _ = await AppNotificationService.requestAuthorizationIfNeeded()
        ImageBackgroundKeeper.shared.begin(reason: "NOCO Magischer Radierer")
        ImageLiveActivityManager.start(prompt: "🪄 \(prompt)")
        ImageLiveActivityManager.update(
            progress: 0.08,
            status: "Radierer startet…",
            insight: "PC bereitet Stable Diffusion vor…",
            etaSeconds: 180,
            phase: .preparing,
            force: true
        )

        let progressTask = Task {
            var waitedAtHold = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 320_000_000)
                let real = await connection.images.peekProgress()
                await MainActor.run {
                    if real > 0.05 {
                        workProgress = max(workProgress, min(0.97, 0.2 + real * 0.75))
                        status = real < 0.9 ? "Stable Diffusion zeichnet…" : "Fast fertig…"
                        ImageLiveActivityManager.update(
                            progress: workProgress,
                            status: status,
                            insight: "Nur die Maske wird neu gezeichnet",
                            etaSeconds: max(15, Int((1 - workProgress) * 120)),
                            phase: .rendering,
                            force: false
                        )
                        return
                    }
                    if workProgress < 0.88 {
                        workProgress = min(0.88, workProgress + Double.random(in: 0.02...0.045))
                        if workProgress < 0.28 {
                            status = "Bilder-Engine prüfen…"
                        } else if workProgress < 0.55 {
                            status = preset == .erase ? "Entfernen…" : "Magie…"
                        } else {
                            status = "Detail neu zeichnen…"
                        }
                        ImageLiveActivityManager.update(
                            progress: workProgress,
                            status: status,
                            insight: "Engine kann 1–2 Min brauchen",
                            etaSeconds: 150,
                            phase: workProgress < 0.35 ? .preparing : .rendering,
                            force: false
                        )
                    } else {
                        waitedAtHold += 1
                        workProgress = min(0.97, workProgress + 0.003)
                        if waitedAtHold < 40 {
                            status = "PC arbeitet noch… bitte warten"
                        } else if waitedAtHold < 90 {
                            status = "Immer noch am PC — oft kalter SD-Start (1–2 Min)"
                        } else {
                            status = "Lange Wartezeit — bitte kurz warten oder Verbindung prüfen"
                        }
                        ImageLiveActivityManager.update(
                            progress: workProgress,
                            status: status,
                            insight: "Hintergrund aktiv — Notification bei Fertig",
                            etaSeconds: 90,
                            phase: .rendering,
                            force: waitedAtHold % 5 == 0
                        )
                    }
                }
            }
        }

        let sdPrompt = ImageAttachIntent.editPrompt(from: prompt)
        let denoise = ImageAttachIntent.denoising(for: prompt)

        do {
            if connection.status.stableDiffusion != true {
                status = "Bilder-Engine startet zuerst…"
                workProgress = max(workProgress, 0.15)
                _ = await connection.images.prepareEngine()
                await connection.refreshStatus(showLoading: false)
            }

            let result = try await connection.images.runInpaint(
                prompt: sdPrompt,
                imageJPEG: jpeg,
                maskPNG: maskForSD,
                denoisingStrength: denoise
            )
            progressTask.cancel()
            workProgress = 1
            status = "Fertig"
            if let b64 = result.imageBase64 {
                let cleaned = b64
                    .replacingOccurrences(of: "\n", with: "")
                    .replacingOccurrences(of: "data:image/png;base64,", with: "")
                    .replacingOccurrences(of: "data:image/jpeg;base64,", with: "")
                if let data = Data(base64Encoded: cleaned), let ui = UIImage(data: data) {
                    try? await Task.sleep(nanoseconds: 320_000_000)
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                        isWorking = false
                        resultImage = ui
                    }
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.78).delay(0.05)) {
                        revealResult = true
                    }
                    status = "Fertig ✨"
                    HapticService.success()
                    connection.images.ingestEditedImage(
                        prompt: prompt,
                        localData: data,
                        path: result.resolvedPath
                    )
                    ImageLiveActivityManager.complete(prompt: "🪄 \(prompt)")
                    await AppNotificationService.notifyEraserReady(prompt: prompt)
                    ImageBackgroundKeeper.shared.end(preserveAudioSession: true)
                } else {
                    isWorking = false
                    ImageLiveActivityManager.fail("Bild unlesbar")
                    await AppNotificationService.notifyImageFailed("Radierer: Bild unlesbar")
                    ImageBackgroundKeeper.shared.end(preserveAudioSession: true)
                    presentError("Bild konnte nicht gelesen werden")
                    HapticService.error()
                }
            } else if result.resolvedPath != nil {
                isWorking = false
                status = "Fertig — siehe Galerie"
                HapticService.success()
                ImageLiveActivityManager.complete(prompt: "🪄 \(prompt)")
                await AppNotificationService.notifyEraserReady(prompt: prompt)
                ImageBackgroundKeeper.shared.end(preserveAudioSession: true)
            } else {
                isWorking = false
                ImageLiveActivityManager.fail("Keine Bilddaten")
                await AppNotificationService.notifyImageFailed("Radierer: keine Bilddaten")
                ImageBackgroundKeeper.shared.end(preserveAudioSession: true)
                presentError("Keine Bilddaten vom PC")
                HapticService.error()
            }
        } catch {
            progressTask.cancel()
            isWorking = false
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            ImageLiveActivityManager.fail(msg)
            await AppNotificationService.notifyImageFailed(msg)
            ImageBackgroundKeeper.shared.end(preserveAudioSession: true)
            presentError(msg)
            HapticService.error()
        }
    }
}

// MARK: - Rainbow Intelligence eraser theater

private struct MagicEraserTheater: View {
    var progress: Double
    var status: String

    @State private var spin = false
    @State private var pulse = false
    @State private var spark = false
    @State private var ripple = false
    @State private var hue = false

    private var pct: Int { Int((min(max(progress, 0), 1) * 100).rounded()) }

    private let rainbow: [Color] = [
        Color(red: 0.35, green: 0.8, blue: 1),
        Color(red: 0.45, green: 0.45, blue: 1),
        Color(red: 0.85, green: 0.4, blue: 1),
        Color(red: 0.95, green: 0.45, blue: 0.7),
        Color(red: 1.0, green: 0.7, blue: 0.35),
        Color(red: 0.4, green: 0.95, blue: 0.7),
        Color(red: 0.35, green: 0.8, blue: 1)
    ]

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let h = max(geo.size.height, 1)
            ZStack {
                // Opaque full-bleed veil — photo silhouette must not show through
                Color.black.opacity(0.94)
                    .frame(width: w * 1.2, height: h * 1.2)
                    .position(x: w / 2, y: h / 2)
                    .ignoresSafeArea()

                // Extra soft vignette so edges stay solid black
                RadialGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    center: .center,
                    startRadius: min(w, h) * 0.2,
                    endRadius: max(w, h) * 0.85
                )
                .frame(width: w * 1.15, height: h * 1.15)
                .position(x: w / 2, y: h / 2)
                .allowsHitTesting(false)

                // Wide aurora — fills the screen so you don't see a round cutout
                AngularGradient(colors: rainbow, center: .center)
                    .frame(width: w * 1.85, height: h * 1.85)
                    .blur(radius: 78)
                    .opacity(pulse ? 0.62 : 0.32)
                    .scaleEffect(pulse ? 1.18 : 1.02)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .blendMode(.plusLighter)
                    .position(x: w / 2, y: h / 2)

                Capsule()
                    .fill(LinearGradient(
                        colors: [.clear, .white.opacity(0.7), rainbow[2].opacity(0.5), .clear],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: min(w * 1.2, 560), height: 110)
                    .rotationEffect(.degrees(-18))
                    .offset(x: hue ? w * 0.38 : -w * 0.38, y: -h * 0.12)
                    .blur(radius: 16)
                    .blendMode(.plusLighter)

                VStack(spacing: 22) {
                    ZStack {
                        AngularGradient(colors: rainbow, center: .center)
                            .frame(width: min(w * 0.82, 360), height: min(w * 0.82, 360))
                            .blur(radius: 56)
                            .opacity(pulse ? 0.8 : 0.42)
                            .scaleEffect(pulse ? 1.14 : 0.94)
                            .rotationEffect(.degrees(spin ? 360 : 0))
                            .blendMode(.plusLighter)

                        ForEach(0..<4, id: \.self) { i in
                            Circle()
                                .stroke(rainbow[i].opacity(ripple ? 0.05 : 0.42 - Double(i) * 0.08), lineWidth: 2.4)
                                .frame(
                                    width: min(w * 0.44, 168) + CGFloat(i * 44),
                                    height: min(w * 0.44, 168) + CGFloat(i * 44)
                                )
                                .scaleEffect(ripple ? 1.38 : 0.92)
                        }

                        Circle()
                            .stroke(AngularGradient(colors: rainbow, center: .center), lineWidth: 8)
                            .frame(width: min(w * 0.38, 158), height: min(w * 0.38, 158))
                            .rotationEffect(.degrees(spin ? 360 : 0))
                            .shadow(color: Color(red: 0.7, green: 0.4, blue: 1).opacity(0.9), radius: 28)

                        Circle()
                            .trim(from: 0, to: max(0.04, min(progress, 1)))
                            .stroke(
                                AngularGradient(colors: [.white, rainbow[0], rainbow[5]], center: .center),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                            .frame(width: min(w * 0.32, 132), height: min(w * 0.32, 132))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.3), value: progress)

                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.white)
                            .symbolEffect(.pulse, options: .repeating)
                            .symbolEffect(.bounce, value: pct / 5)
                            .scaleEffect(pulse ? 1.12 : 0.94)

                        ForEach(0..<16, id: \.self) { i in
                            Image(systemName: "sparkle")
                                .font(.system(size: CGFloat(5 + i % 5 * 2), weight: .bold))
                                .foregroundStyle(rainbow[i % (rainbow.count - 1)].opacity(spark ? 1 : 0.12))
                                .offset(
                                    x: cos(Double(i) / 16 * .pi * 2) * (spark ? min(w * 0.3, 118) : min(w * 0.22, 88)),
                                    y: sin(Double(i) / 16 * .pi * 2) * (spark ? min(w * 0.3, 118) : min(w * 0.22, 88))
                                )
                                .scaleEffect(spark ? 1.3 : 0.45)
                        }
                    }
                    .frame(height: min(w * 0.74, 310))
                    .hueRotation(.degrees(hue ? 36 : -18))

                    VStack(spacing: 8) {
                        Text("Magischer Radierer")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .textCase(.uppercase)
                            .tracking(1.2)
                        Text("\(pct)%")
                            .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .shadow(color: rainbow[2].opacity(0.6), radius: 14)
                        Text(status)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                        Text(pct >= 88 ? "Normal — PC / Stable Diffusion arbeitet noch" : "Apple Intelligence · nur die Maske")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                    .frame(maxWidth: min(w - 28, 380))
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(0.95))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(AngularGradient(colors: rainbow, center: .center), lineWidth: 1.8)
                            )
                            .shadow(color: rainbow[2].opacity(0.45), radius: 26, y: 10)
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
        .allowsHitTesting(true)
        .onAppear {
            withAnimation(.linear(duration: 1.9).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { spark = true }
            withAnimation(.easeOut(duration: 1.15).repeatForever(autoreverses: false)) { ripple = true }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { hue = true }
            HapticService.medium()
        }
    }
}

// MARK: - Canvas

enum MaskSelectTool: String, CaseIterable, Identifiable {
    case paint
    case auto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paint: return "Pinsel"
        case .auto: return "Auto"
        }
    }

    var systemImage: String {
        switch self {
        case .paint: return "paintbrush.pointed.fill"
        case .auto: return "circle.dashed"
        }
    }
}

final class MaskCanvasController: ObservableObject {
    weak var drawView: MaskDrawView?
    var hasPaint: Bool { drawView?.hasPaint == true }

    func clear() {
        drawView?.clear()
        objectWillChange.send()
    }

    func exportMaskPNG(matching image: UIImage) -> Data? {
        drawView?.exportMaskPNG(targetSize: image.size)
    }

    func notifyPaintChanged() {
        objectWillChange.send()
    }
}

struct MaskPaintCanvas: UIViewRepresentable {
    let image: UIImage
    @ObservedObject var controller: MaskCanvasController
    var brushSize: CGFloat
    var tool: MaskSelectTool
    var onPaintingChange: ((Bool) -> Void)?
    var onMaskChanged: ((Bool) -> Void)?
    var onAutoBusy: ((Bool) -> Void)?

    func makeUIView(context: Context) -> MaskDrawView {
        let v = MaskDrawView(image: image)
        v.brushSize = brushSize
        v.tool = tool
        v.onPaintingChange = onPaintingChange
        v.onMaskChanged = { painted in
            controller.notifyPaintChanged()
            onMaskChanged?(painted)
        }
        v.onAutoBusy = onAutoBusy
        controller.drawView = v
        return v
    }

    func updateUIView(_ uiView: MaskDrawView, context: Context) {
        uiView.brushSize = brushSize
        uiView.tool = tool
        uiView.onPaintingChange = onPaintingChange
        uiView.onMaskChanged = { painted in
            controller.notifyPaintChanged()
            onMaskChanged?(painted)
        }
        uiView.onAutoBusy = onAutoBusy
        if uiView.baseImage.size != image.size {
            uiView.setBaseImage(image)
        }
        controller.drawView = uiView
    }
}

final class MaskDrawView: UIView {
    private(set) var baseImage: UIImage
    private var maskLayer = CAShapeLayer()
    private var cursorLayer = CAShapeLayer()
    private var path = UIBezierPath()
    private(set) var hasPaint = false
    var brushSize: CGFloat = 36 {
        didSet { updateCursor() }
    }
    var tool: MaskSelectTool = .paint {
        didSet {
            cursorLayer.isHidden = tool != .auto
            updateCursor()
        }
    }
    var onPaintingChange: ((Bool) -> Void)?
    var onMaskChanged: ((Bool) -> Void)?
    var onAutoBusy: ((Bool) -> Void)?
    private var strokeHue: CGFloat = 0.55
    private var strokeSamples = 0
    private var lastTouch: CGPoint = .zero
    private var autoTask: Task<Void, Never>?

    init(image: UIImage) {
        self.baseImage = image
        super.init(frame: .zero)
        isMultipleTouchEnabled = false
        backgroundColor = .black
        contentMode = .scaleAspectFit
        maskLayer.strokeColor = UIColor(hue: strokeHue, saturation: 0.9, brightness: 1, alpha: 0.72).cgColor
        maskLayer.fillColor = UIColor(hue: strokeHue, saturation: 0.85, brightness: 1, alpha: 0.28).cgColor
        maskLayer.lineCap = .round
        maskLayer.lineJoin = .round
        layer.addSublayer(maskLayer)

        cursorLayer.fillColor = UIColor.clear.cgColor
        cursorLayer.strokeColor = UIColor.systemCyan.withAlphaComponent(0.95).cgColor
        cursorLayer.lineWidth = 2
        cursorLayer.lineDashPattern = [6, 4]
        cursorLayer.isHidden = true
        layer.addSublayer(cursorLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setBaseImage(_ image: UIImage) {
        baseImage = image
        clear()
        setNeedsDisplay()
    }

    func clear() {
        autoTask?.cancel()
        path = UIBezierPath()
        maskLayer.path = nil
        hasPaint = false
        strokeSamples = 0
        onMaskChanged?(false)
        updateCursor()
    }

    override func draw(_ rect: CGRect) {
        let drawRect = aspectFitRect(for: baseImage.size, in: bounds)
        baseImage.draw(in: drawRect)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        maskLayer.frame = bounds
        cursorLayer.frame = bounds
        setNeedsDisplay()
        updateCursor()
    }

    private func updateCursor(at point: CGPoint? = nil) {
        guard tool == .auto else {
            cursorLayer.path = nil
            return
        }
        let center = point ?? lastTouch
        let r = max(18, brushSize * 0.55)
        guard center != .zero || point != nil else {
            cursorLayer.path = nil
            return
        }
        cursorLayer.path = UIBezierPath(
            ovalIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        ).cgPath
    }

    private func setParentScrollEnabled(_ enabled: Bool) {
        var view: UIView? = self
        while let current = view {
            if let scroll = current as? UIScrollView {
                scroll.isScrollEnabled = enabled
                scroll.panGestureRecognizer.isEnabled = enabled
                scroll.delaysContentTouches = enabled
                scroll.canCancelContentTouches = enabled
            }
            view = current.superview
        }
        onPaintingChange?(!enabled)
    }

    private func advanceRainbowStroke() {
        strokeHue = strokeHue + 0.035
        if strokeHue > 1 { strokeHue -= 1 }
        maskLayer.strokeColor = UIColor(hue: strokeHue, saturation: 0.92, brightness: 1, alpha: 0.75).cgColor
        maskLayer.fillColor = UIColor(hue: strokeHue, saturation: 0.85, brightness: 1, alpha: 0.28).cgColor
    }

    private func markPainted() {
        guard !hasPaint else { return }
        hasPaint = true
        onMaskChanged?(true)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let p = touches.first?.location(in: self) else { return }
        lastTouch = p
        updateCursor(at: p)

        if tool == .auto {
            setParentScrollEnabled(false)
            HapticService.whisper()
            runAutoSelect(at: p)
            return
        }

        setParentScrollEnabled(false)
        strokeSamples = 0
        path.move(to: p)
        path.lineWidth = brushSize
        advanceRainbowStroke()
        HapticService.whisper()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let p = touches.first?.location(in: self) else { return }
        lastTouch = p
        updateCursor(at: p)
        guard tool == .paint else { return }
        strokeSamples += 1
        path.addLine(to: p)
        path.lineWidth = brushSize
        maskLayer.path = path.cgPath
        maskLayer.lineWidth = brushSize
        advanceRainbowStroke()
        markPainted()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer { setParentScrollEnabled(true) }
        guard tool == .paint else { return }
        if strokeSamples == 0 {
            let dab = UIBezierPath(
                ovalIn: CGRect(
                    x: lastTouch.x - brushSize * 0.35,
                    y: lastTouch.y - brushSize * 0.35,
                    width: brushSize * 0.7,
                    height: brushSize * 0.7
                )
            )
            path.append(dab)
            maskLayer.path = path.cgPath
            maskLayer.lineWidth = brushSize
            markPainted()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        setParentScrollEnabled(true)
    }

    private func runAutoSelect(at viewPoint: CGPoint) {
        autoTask?.cancel()
        onAutoBusy?(true)
        let image = baseImage
        let fit = aspectFitRect(for: image.size, in: bounds)
        let brush = brushSize
        autoTask = Task.detached(priority: .userInitiated) {
            let region = MaskAutoSelect.fastRegion(
                image: image,
                viewPoint: viewPoint,
                imageRectInView: fit,
                radiusHint: brush
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.onAutoBusy?(false)
                guard !Task.isCancelled else { return }
                guard let region, !region.isEmpty else {
                    HapticService.warning()
                    return
                }
                self.advanceRainbowStroke()
                self.path.append(region)
                self.maskLayer.path = self.path.cgPath
                self.maskLayer.lineWidth = max(2, self.brushSize * 0.15)
                self.markPainted()
                HapticService.success()
            }
        }
    }

    /// A1111: white = inpaint, black = keep
    func exportMaskPNG(targetSize: CGSize) -> Data? {
        let w = max(1, Int(targetSize.width.rounded()))
        let h = max(1, Int(targetSize.height.rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format)
        let img = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            let fit = aspectFitRect(for: targetSize, in: bounds)
            guard fit.width > 0, fit.height > 0 else { return }
            let sx = CGFloat(w) / fit.width
            let sy = CGFloat(h) / fit.height
            ctx.cgContext.translateBy(x: -fit.origin.x * sx, y: -fit.origin.y * sy)
            ctx.cgContext.scaleBy(x: sx, y: sy)
            UIColor.white.setFill()
            UIColor.white.setStroke()
            let exportPath = path.copy() as? UIBezierPath ?? path
            exportPath.lineWidth = brushSize
            exportPath.lineCapStyle = .round
            exportPath.lineJoinStyle = .round
            exportPath.fill()
            exportPath.stroke()
        }
        return img.pngData()
    }

    private func aspectFitRect(for size: CGSize, in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let w = size.width * scale
        let h = size.height * scale
        return CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
    }
}

/// Ultra-fast local object pick: color flood-fill on a tiny preview + soft radius bias.
enum MaskAutoSelect {
    static func fastRegion(
        image: UIImage,
        viewPoint: CGPoint,
        imageRectInView: CGRect,
        radiusHint: CGFloat
    ) -> UIBezierPath? {
        guard imageRectInView.width > 1, imageRectInView.height > 1,
              let cg = image.cgImage else { return nil }

        let ix = (viewPoint.x - imageRectInView.minX) / imageRectInView.width
        let iy = (viewPoint.y - imageRectInView.minY) / imageRectInView.height
        guard ix >= 0, ix <= 1, iy >= 0, iy <= 1 else { return nil }

        let maxSide = 160
        let srcW = cg.width
        let srcH = cg.height
        let scale = min(CGFloat(maxSide) / CGFloat(srcW), CGFloat(maxSide) / CGFloat(srcH), 1)
        let w = max(8, Int((CGFloat(srcW) * scale).rounded()))
        let h = max(8, Int((CGFloat(srcH) * scale).rounded()))

        guard let tiny = downsample(cg, width: w, height: h),
              let data = tiny.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }

        let bpp = tiny.bitsPerPixel / 8
        let bpr = tiny.bytesPerRow
        let sx = min(w - 1, max(0, Int(ix * CGFloat(w))))
        let sy = min(h - 1, max(0, Int(iy * CGFloat(h))))

        func sample(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let o = y * bpr + x * bpp
            return (Int(ptr[o]), Int(ptr[o + 1]), Int(ptr[o + 2]))
        }

        let seed = sample(sx, sy)
        // Tighter first pass, then slight expand for cleaner edges.
        let tol = 32
        var visited = [UInt8](repeating: 0, count: w * h)
        var stack = [(sx, sy)]
        visited[sy * w + sx] = 1
        var filled = [(Int, Int)]()
        filled.reserveCapacity(2048)
        let maxPixels = w * h / 2

        while let (x, y) = stack.popLast(), filled.count < maxPixels {
            let c = sample(x, y)
            let dr = abs(c.r - seed.r)
            let dg = abs(c.g - seed.g)
            let db = abs(c.b - seed.b)
            // Weighted RGB distance — edges stay sharper than flat sum.
            let dist = dr * 2 + dg * 3 + db
            guard dist <= tol * 5 else { continue }
            filled.append((x, y))
            let n = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1),
                     (x + 1, y + 1), (x - 1, y - 1), (x + 1, y - 1), (x - 1, y + 1)]
            for (nx, ny) in n {
                guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                let i = ny * w + nx
                if visited[i] == 0 {
                    visited[i] = 1
                    stack.append((nx, ny))
                }
            }
        }

        // Morphological expand 1px for smoother outline
        var expanded = filled
        for (x, y) in filled {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                let i = ny * w + nx
                if visited[i] == 0 {
                    visited[i] = 1
                    expanded.append((nx, ny))
                }
            }
        }
        filled = expanded

        // Soft circle bias around tap so thin objects still get coverage
        let rPix = max(3, Int((radiusHint / imageRectInView.width) * CGFloat(w) * 0.5))
        for dy in -rPix...rPix {
            for dx in -rPix...rPix where dx * dx + dy * dy <= rPix * rPix {
                let x = sx + dx, y = sy + dy
                guard x >= 0, y >= 0, x < w, y < h else { continue }
                let i = y * w + x
                if visited[i] == 0 {
                    visited[i] = 1
                    filled.append((x, y))
                }
            }
        }

        guard filled.count > 8 else { return nil }

        let path = UIBezierPath()
        let cellW = imageRectInView.width / CGFloat(w)
        let cellH = imageRectInView.height / CGFloat(h)
        let stamp = max(cellW, cellH) * 1.15
        for (x, y) in filled {
            let cx = imageRectInView.minX + (CGFloat(x) + 0.5) * cellW
            let cy = imageRectInView.minY + (CGFloat(y) + 0.5) * cellH
            path.append(UIBezierPath(ovalIn: CGRect(
                x: cx - stamp * 0.5,
                y: cy - stamp * 0.5,
                width: stamp,
                height: stamp
            )))
        }
        return path
    }

    private static func downsample(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}


private extension UIImage {
    func resizedToFit(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
