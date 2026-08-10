import PhotosUI
import SwiftUI
import UIKit

/// Magischer AI-Radierer 2.0: Foto → Auto/Malen → Entfernen/Ersetzen → Theater → Vorher|Nachher.
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

        var intentMode: ImageAttachIntent.EraserMode {
            switch self {
            case .erase: return .erase
            case .replace: return .replace
            case .custom: return .custom
            }
        }

        var defaultText: String {
            switch self {
            case .erase: return "Entferne den markierten Bereich und fülle natürlich mit dem Hintergrund."
            case .replace: return ""
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
    @State private var quality: ImageGenMode = .think
    @State private var instruction = Preset.erase.defaultText
    @State private var isWorking = false
    @State private var workProgress: Double = 0
    @State private var theaterStage = 0
    @State private var status = "Foto wählen · bemalen oder Antippen"
    @State private var resultImage: UIImage?
    @State private var beforeImage: UIImage?
    @State private var canvas = MaskCanvasController()
    @State private var showLibrary = false
    @State private var revealResult = false
    @State private var compareSplit: CGFloat = 1.0
    @State private var showBefore = false
    @State private var maskPulse = false
    @State private var isPainting = false
    @State private var maskReady = false
    @State private var errorAlert: String?
    @State private var isAutoSelecting = false
    @State private var appear = false
    @State private var historyTick = 0
    @State private var workTask: Task<Void, Never>?
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

                if let resultImage, let before = beforeImage ?? sourceImage {
                    resultCard(before: before, after: resultImage)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 16)
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 18)
            .scaleEffect(appear ? 1 : 0.98)
        }
        .nocoBackground()
        .overlay {
            if appear {
                FloatingIntelligenceDots(count: 5)
                    .opacity(0.1)
                    .allowsHitTesting(false)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionButtons
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 10)
                .background {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(alignment: .top) {
                            NOCORainbowFlowLine(height: 1)
                                .opacity(0.45)
                        }
                        .ignoresSafeArea(edges: .bottom)
                        .shadow(color: .black.opacity(0.12), radius: 12, y: -4)
                }
        }
        .overlay {
            if isWorking {
                MagicEraserTheater(
                    progress: workProgress,
                    status: status,
                    stage: theaterStage,
                    preset: preset,
                    onCancel: { Task { await cancelEraser() } }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: isWorking)
        .navigationTitle("Magischer Radierer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            connection.hideMainTabBar = true
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                appear = true
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                maskPulse = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nocoInpaintSoftReconnect)) { _ in
            guard isWorking else { return }
            status = "Verbindung kurz unterbrochen – Verarbeitung wird fortgesetzt…"
        }
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
                        historyTick &+= 1
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
                    if maskReady && !isWorking {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                AngularGradient(
                                    colors: NOCORainbow.flow.map { $0.opacity(maskPulse ? 0.55 : 0.2) },
                                    center: .center
                                ),
                                lineWidth: 1.5
                            )
                            .padding(8)
                            .allowsHitTesting(false)
                    }
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(NOCOAITheme.accent.opacity(0.85))
                    Text("Foto wählen")
                        .font(.headline)
                    Text("Dann bemalen oder Objekt antippen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        HapticService.light()
                        showLibrary = true
                    } label: {
                        Label("Foto wählen", systemImage: "photo")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 11)
                            .background(
                                LinearGradient(
                                    colors: Array(NOCORainbow.flow.prefix(4)),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: Capsule()
                            )
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(IntelligencePressStyle())
                }
                .padding(36)
            }
        }
        .frame(minHeight: 340)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    AngularGradient(
                        colors: NOCORainbow.flow.map { $0.opacity(0.35) },
                        center: .center
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: NOCORainbow.violet.opacity(0.12), radius: 18, y: 8)
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
                if p == .erase {
                    instruction = p.defaultText
                } else if instruction == Preset.erase.defaultText {
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

            Picker("Qualität", selection: $quality) {
                Text(ImageGenMode.flash.title).tag(ImageGenMode.flash)
                Text(ImageGenMode.think.title).tag(ImageGenMode.think)
            }
            .pickerStyle(.segmented)

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
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(IntelligencePressStyle())

                Button {
                    HapticService.soft()
                    canvas.undo()
                    historyTick &+= 1
                    maskReady = canvas.hasPaint
                    status = canvas.hasPaint ? "Maske angepasst" : (selectTool == .auto ? "Objekt antippen" : "Bereich bemalen")
                } label: {
                    Label("Rückgängig", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(IntelligencePressStyle())
                .disabled(!canvas.canUndo || isWorking || isAutoSelecting)
                .opacity(canvas.canUndo ? 1 : 0.45)

                Button {
                    HapticService.soft()
                    canvas.redo()
                    historyTick &+= 1
                    maskReady = canvas.hasPaint
                } label: {
                    Label("Wiederholen", systemImage: "arrow.uturn.forward")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(IntelligencePressStyle())
                .disabled(!canvas.canRedo || isWorking || isAutoSelecting)
                .opacity(canvas.canRedo ? 1 : 0.45)
            }
            .id(historyTick)
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
            workTask = Task { await runEraser() }
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
                    colors: Array(NOCORainbow.flow.prefix(5)),
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(IntelligencePrimaryPressStyle(haptic: { HapticService.medium() }))
        .disabled(isWorking || sourceImage == nil || !canApply || !maskReady)
        .opacity(sourceImage == nil || !maskReady ? 0.5 : 1)
    }

    private var canApply: Bool {
        if preset == .replace {
            return !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if preset == .custom {
            return !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private var effectivePrompt: String {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if preset == .erase && trimmed.isEmpty {
            return Preset.erase.defaultText
        }
        return trimmed
    }

    private func resultCard(before: UIImage, after: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ergebnis")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker("Vergleich", selection: $showBefore) {
                    Text("Nachher").tag(false)
                    Text("Vorher").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
                .onChange(of: showBefore) { _, show in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        compareSplit = show ? 0 : 1
                    }
                }
            }

            BeforeAfterWipe(before: before, after: after, split: $compareSplit)
                .frame(minHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            AngularGradient(colors: NOCORainbow.flow.map { $0.opacity(0.4) }, center: .center),
                            lineWidth: 1
                        )
                )
                .shadow(color: NOCORainbow.violet.opacity(0.28), radius: 14)
                .scaleEffect(revealResult ? 1 : 0.92)
                .opacity(revealResult ? 1 : 0)
                .blur(radius: revealResult ? 0 : 12)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: revealResult)

            VStack(alignment: .leading, spacing: 6) {
                Text("Vergleich ziehen")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $compareSplit, in: 0...1)
                    .tint(NOCOAITheme.accent)
            }

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) {
                        sourceImage = after
                        resultImage = nil
                        beforeImage = nil
                        revealResult = false
                        maskReady = false
                        canvas.clear()
                        historyTick &+= 1
                        status = "Weiter bearbeiten — neu bemalen"
                    }
                    HapticService.open()
                } label: {
                    Label("Weiter bearbeiten", systemImage: "paintbrush.pointed")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(IntelligencePressStyle())

                Button {
                    UIImageWriteToSavedPhotosAlbum(after, nil, nil, nil)
                    HapticService.success()
                    status = "In Fotos gespeichert"
                } label: {
                    Label("Speichern", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(IntelligencePressStyle())
            }
        }
        .padding(14)
        .nocoGlass(cornerRadius: 18)
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        if let data = await ChatPhotoLoader.loadJPEG(from: item),
           let ui = UIImage(data: data) {
            sourceImage = ui
            resultImage = nil
            beforeImage = nil
            revealResult = false
            maskReady = false
            canvas.clear()
            historyTick &+= 1
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

    private func cancelEraser() async {
        workTask?.cancel()
        try? await connection.images.apiInterrupt()
        isWorking = false
        workProgress = 0
        theaterStage = 0
        status = "Abgebrochen"
        ImageLiveActivityManager.fail("Abgebrochen")
        ImageBackgroundKeeper.shared.end(preserveAudioSession: true)
        HapticService.warning()
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
        guard !prompt.isEmpty else {
            if preset == .replace {
                presentError("Bitte angeben, wodurch ersetzt werden soll")
            }
            return
        }

        guard maskReady, canvas.hasPaint,
              canvas.exportMaskPNG(matching: sourceImage) != nil else {
            presentError("Bitte zuerst einen Bereich bemalen")
            HapticService.warning()
            return
        }

        let sizeInfo = ImageAttachIntent.inpaintSize(for: sourceImage.size, quality: quality)
        let working = sourceImage.resizedToFit(maxSide: CGFloat(max(sizeInfo.width, sizeInfo.height)))
        guard let jpeg = working.jpegData(compressionQuality: 0.9),
              let maskForSD = canvas.exportMaskPNG(matching: working) else {
            presentError("Maske konnte nicht exportiert werden — nochmal bemalen")
            return
        }

        let mode = preset.intentMode
        let sdPrompt = ImageAttachIntent.editPrompt(from: prompt, mode: mode)
        let denoise = ImageAttachIntent.denoising(for: prompt, mode: mode, quality: quality)
        let steps = ImageAttachIntent.inpaintSteps(mode: mode, quality: quality)
        let dims = ImageAttachIntent.inpaintSize(for: working.size, quality: quality)

        beforeImage = sourceImage
        isWorking = true
        workProgress = 0.06
        theaterStage = 0
        promptFocused = false
        showBefore = false
        compareSplit = 1
        status = "NOCO analysiert…"
        HapticService.medium()

        _ = await AppNotificationService.requestAuthorizationIfNeeded()
        ImageBackgroundKeeper.shared.begin(reason: "NOCO Magischer Radierer")
        ImageLiveActivityManager.start(prompt: "🪄 \(prompt)", owner: .eraser)
        ImageLiveActivityManager.update(
            progress: 0.06,
            status: "NOCO analysiert…",
            insight: "PC bereitet Stable Diffusion vor…",
            etaSeconds: quality == .flash ? 90 : 180,
            phase: .preparing,
            force: true
        )

        let progressTask = Task {
            var waitedAtHold = 0
            var softNoteShown = false
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 320_000_000)
                let real = await connection.images.peekProgress()
                await MainActor.run {
                    if real > 0.05 {
                        workProgress = max(workProgress, min(0.97, 0.2 + real * 0.75))
                        if workProgress < 0.45 {
                            theaterStage = 1
                            status = preset == .erase ? "Objekt wird entfernt…" : "Objekt wird ersetzt…"
                        } else if workProgress < 0.85 {
                            theaterStage = 2
                            status = "Details werden rekonstruiert…"
                        } else {
                            theaterStage = 3
                            status = "Fast fertig…"
                        }
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
                        if workProgress < 0.22 {
                            theaterStage = 0
                            status = "NOCO analysiert…"
                        } else if workProgress < 0.55 {
                            theaterStage = 1
                            status = preset == .erase ? "Objekt wird entfernt…" : "Objekt wird ersetzt…"
                        } else {
                            theaterStage = 2
                            status = "Details werden rekonstruiert…"
                        }
                        ImageLiveActivityManager.update(
                            progress: workProgress,
                            status: status,
                            insight: "Engine kann 1–2 Min brauchen",
                            etaSeconds: quality == .flash ? 90 : 150,
                            phase: workProgress < 0.35 ? .preparing : .rendering,
                            force: false
                        )
                    } else {
                        waitedAtHold += 1
                        workProgress = min(0.97, workProgress + 0.003)
                        theaterStage = 2
                        if waitedAtHold < 40 {
                            status = "Details werden rekonstruiert…"
                        } else if waitedAtHold < 90 {
                            if !softNoteShown {
                                softNoteShown = true
                                status = "Verbindung kurz unterbrochen – Verarbeitung wird fortgesetzt…"
                            } else {
                                status = "PC arbeitet noch… bitte warten"
                            }
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

        do {
            if connection.status.stableDiffusion != true {
                status = "NOCO analysiert…"
                theaterStage = 0
                workProgress = max(workProgress, 0.12)
                _ = await connection.images.prepareEngine()
                await connection.refreshStatus(showLoading: false)
            }

            try Task.checkCancellation()

            let result = try await connection.images.runInpaint(
                prompt: sdPrompt,
                imageJPEG: jpeg,
                maskPNG: maskForSD,
                denoisingStrength: denoise,
                steps: steps,
                width: dims.width,
                height: dims.height,
                mode: mode.rawValue,
                quality: quality
            )
            progressTask.cancel()
            try Task.checkCancellation()
            workProgress = 1
            theaterStage = 3
            status = "Fertig"

            func finishWith(_ ui: UIImage, data: Data, path: String?) {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                    isWorking = false
                    resultImage = ui
                    compareSplit = 1
                    showBefore = false
                }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.78).delay(0.05)) {
                    revealResult = true
                }
                status = "Fertig"
                HapticService.success()
                connection.images.ingestEditedImage(
                    prompt: prompt,
                    localData: data,
                    path: path
                )
                ImageLiveActivityManager.complete(prompt: "🪄 \(prompt)")
            }

            if let b64 = result.imageBase64 {
                let cleaned = b64
                    .replacingOccurrences(of: "\n", with: "")
                    .replacingOccurrences(of: "data:image/png;base64,", with: "")
                    .replacingOccurrences(of: "data:image/jpeg;base64,", with: "")
                if let data = Data(base64Encoded: cleaned), let ui = UIImage(data: data) {
                    try? await Task.sleep(nanoseconds: 280_000_000)
                    finishWith(ui, data: data, path: result.resolvedPath)
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
            } else if let path = result.resolvedPath, let url = connection.images.mediaURL(for: path) {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let ui = UIImage(data: data) {
                        try? await Task.sleep(nanoseconds: 280_000_000)
                        finishWith(ui, data: data, path: path)
                        await AppNotificationService.notifyEraserReady(prompt: prompt)
                        ImageBackgroundKeeper.shared.end(preserveAudioSession: true)
                    } else {
                        isWorking = false
                        status = "Fertig — siehe Galerie"
                        HapticService.success()
                        ImageLiveActivityManager.complete(prompt: "🪄 \(prompt)")
                        await AppNotificationService.notifyEraserReady(prompt: prompt)
                        ImageBackgroundKeeper.shared.end(preserveAudioSession: true)
                    }
                } catch {
                    isWorking = false
                    status = "Fertig — siehe Galerie"
                    HapticService.success()
                    ImageLiveActivityManager.complete(prompt: "🪄 \(prompt)")
                    await AppNotificationService.notifyEraserReady(prompt: prompt)
                    ImageBackgroundKeeper.shared.end(preserveAudioSession: true)
                }
            } else {
                isWorking = false
                ImageLiveActivityManager.fail("Keine Bilddaten")
                await AppNotificationService.notifyImageFailed("Radierer: keine Bilddaten")
                ImageBackgroundKeeper.shared.end(preserveAudioSession: true)
                presentError("Keine Bilddaten vom PC")
                HapticService.error()
            }
        } catch is CancellationError {
            progressTask.cancel()
            isWorking = false
            status = "Abgebrochen"
            ImageLiveActivityManager.fail("Abgebrochen")
            ImageBackgroundKeeper.shared.end(preserveAudioSession: true)
        } catch {
            progressTask.cancel()
            isWorking = false
            let mapped = error
            if CompanionAPI.isTransient(mapped) {
                status = "Verbindung kurz unterbrochen – Verarbeitung wird fortgesetzt…"
            }
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            ImageLiveActivityManager.fail(msg)
            await AppNotificationService.notifyImageFailed(msg)
            ImageBackgroundKeeper.shared.end(preserveAudioSession: true)
            presentError(msg)
            HapticService.error()
        }
    }
}

// MARK: - Before / After wipe

private struct BeforeAfterWipe: View {
    let before: UIImage
    let after: UIImage
    @Binding var split: CGFloat

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cut = max(0, min(1, split)) * w
            ZStack(alignment: .leading) {
                Image(uiImage: before)
                    .resizable()
                    .scaledToFit()
                    .frame(width: w, height: h)

                Image(uiImage: after)
                    .resizable()
                    .scaledToFit()
                    .frame(width: w, height: h)
                    .mask(
                        HStack(spacing: 0) {
                            Rectangle().frame(width: cut)
                            Spacer(minLength: 0)
                        }
                    )

                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 2, height: h)
                    .offset(x: cut - 1)
                    .shadow(color: .black.opacity(0.35), radius: 2)
            }
        }
        .aspectRatio(
            after.size.width > 0 && after.size.height > 0
                ? after.size.width / after.size.height
                : 1,
            contentMode: .fit
        )
    }
}

// MARK: - Rainbow Intelligence eraser theater

private struct MagicEraserTheater: View {
    var progress: Double
    var status: String
    var stage: Int
    var preset: MagischerRadiererView.Preset
    var onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var glow = false

    private var pct: Int { Int((min(max(progress, 0), 1) * 100).rounded()) }

    private var stageLabel: String {
        switch stage {
        case 0: return "NOCO analysiert…"
        case 1: return preset == .erase ? "Objekt wird entfernt…" : "Objekt wird ersetzt…"
        case 2: return "Details werden rekonstruiert…"
        default: return "Fast fertig…"
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            AngularGradient(colors: NOCORainbow.flow.map { $0.opacity(0.35) }, center: .center)
                .blur(radius: 70)
                .opacity(pulse ? 0.7 : 0.35)
                .scaleEffect(pulse ? 1.12 : 0.96)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(
                            AngularGradient(colors: NOCORainbow.flow, center: .center),
                            lineWidth: 3
                        )
                        .frame(width: 168, height: 168)
                        .blur(radius: glow ? 10 : 2)
                        .opacity(glow ? 0.85 : 0.45)
                        .scaleEffect(glow ? 1.08 : 0.96)

                    NOCOIntelligenceCore(
                        energy: .working,
                        size: .hero,
                        progress: progress,
                        systemImage: "wand.and.stars"
                    )
                    Text("\(pct)%")
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .offset(y: 72)
                        .contentTransition(.numericText())
                }
                .frame(height: 220)

                VStack(spacing: 8) {
                    Text("Magischer Radierer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .textCase(.uppercase)
                        .tracking(1.1)
                    Text(status.isEmpty ? stageLabel : status)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                    NOCORainbowFlowLine(height: 2)
                        .frame(maxWidth: 180)
                        .padding(.top, 4)

                    Button(role: .cancel) {
                        onCancel()
                    } label: {
                        Text("Abbrechen")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 22)
                            .padding(.vertical, 10)
                            .background(.white.opacity(0.12), in: Capsule())
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .background(.ultraThinMaterial.opacity(0.95), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AngularGradient(colors: NOCORainbow.flow, center: .center), lineWidth: 1.2)
                )
            }
            .padding(24)
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { glow = true }
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
        case .paint: return "Malen"
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
    var canUndo: Bool { drawView?.canUndo == true }
    var canRedo: Bool { drawView?.canRedo == true }

    func clear() {
        drawView?.clear()
        objectWillChange.send()
    }

    func undo() {
        drawView?.undo()
        objectWillChange.send()
    }

    func redo() {
        drawView?.redo()
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
    private var undoStack: [UIBezierPath] = []
    private var redoStack: [UIBezierPath] = []
    private(set) var hasPaint = false
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
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
    private var strokeSnapshotTaken = false

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
        if hasPaint || !(path.cgPath.isEmpty) {
            pushUndoIfNeeded()
        }
        path = UIBezierPath()
        maskLayer.path = nil
        hasPaint = false
        strokeSamples = 0
        onMaskChanged?(false)
        updateCursor()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(copyPath(path))
        applyPath(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(copyPath(path))
        applyPath(next)
    }

    private func copyPath(_ source: UIBezierPath) -> UIBezierPath {
        (source.copy() as? UIBezierPath) ?? UIBezierPath()
    }

    private func pushUndoIfNeeded() {
        undoStack.append(copyPath(path))
        if undoStack.count > 40 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func applyPath(_ next: UIBezierPath) {
        path = next
        let empty = path.bounds.isEmpty && path.isEmpty
        // UIBezierPath.isEmpty is true for empty path; also check CGPath element count via bounds
        hasPaint = !(path.cgPath.isEmpty)
        maskLayer.path = hasPaint ? path.cgPath : nil
        maskLayer.lineWidth = brushSize
        onMaskChanged?(hasPaint)
        _ = empty
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
        strokeSnapshotTaken = false
        pushUndoIfNeeded()
        strokeSnapshotTaken = true
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
        onMaskChanged?(hasPaint)
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
                self.pushUndoIfNeeded()
                self.advanceRainbowStroke()
                self.path.append(region)
                self.maskLayer.path = self.path.cgPath
                self.maskLayer.lineWidth = max(2, self.brushSize * 0.15)
                self.markPainted()
                self.onMaskChanged?(true)
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

/// Local object pick: adaptive flood-fill + edge expand for cleaner contours.
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

        let maxSide = 200
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
        // Local variance ??? adaptive tolerance (busy textures get a bit more slack).
        var varSum = 0
        var varCount = 0
        for dy in -2...2 {
            for dx in -2...2 {
                let x = sx + dx, y = sy + dy
                guard x >= 0, y >= 0, x < w, y < h else { continue }
                let c = sample(x, y)
                varSum += abs(c.r - seed.r) + abs(c.g - seed.g) + abs(c.b - seed.b)
                varCount += 1
            }
        }
        let localVar = varCount > 0 ? varSum / varCount : 20
        let tol = min(48, max(24, localVar + 18))

        var visited = [UInt8](repeating: 0, count: w * h)
        var stack = [(sx, sy)]
        visited[sy * w + sx] = 1
        var filled = [(Int, Int)]()
        filled.reserveCapacity(4096)
        let maxPixels = w * h / 2

        while let (x, y) = stack.popLast(), filled.count < maxPixels {
            let c = sample(x, y)
            let dr = abs(c.r - seed.r)
            let dg = abs(c.g - seed.g)
            let db = abs(c.b - seed.b)
            // Weighted RGB ??? green/luma edges stay sharper.
            let dist = dr * 2 + dg * 4 + db
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

        // Morphological close: expand then lightly keep interior (smoother edges).
        var mask = [UInt8](repeating: 0, count: w * h)
        for (x, y) in filled { mask[y * w + x] = 1 }
        var dilated = mask
        for (x, y) in filled {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                dilated[ny * w + nx] = 1
            }
        }
        filled = []
        for y in 0..<h {
            for x in 0..<w where dilated[y * w + x] == 1 {
                filled.append((x, y))
            }
        }

        let rPix = max(2, Int((radiusHint / imageRectInView.width) * CGFloat(w) * 0.42))
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
        let stamp = max(cellW, cellH) * 1.12
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
        ctx.interpolationQuality = .medium
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
