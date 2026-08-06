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
    @State private var preset: Preset = .erase
    @State private var instruction = Preset.erase.defaultText
    @State private var isWorking = false
    @State private var workProgress: Double = 0
    @State private var status = "1 Foto · 2 bemalen · 3 Anweisung · 4 Magisch"
    @State private var resultImage: UIImage?
    @State private var canvas = MaskCanvasController()
    @State private var showLibrary = false
    @State private var revealResult = false
    @State private var maskPulse = false
    @State private var isPainting = false
    @FocusState private var promptFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                canvasCard
                controls
                presetRow
                promptCard
                actionButtons
                if let resultImage {
                    resultCard(resultImage)
                }
            }
            .padding(20)
        }
        .scrollDisabled(isPainting || isWorking)
        .nocoBackground()
        .overlay {
            if isWorking {
                MagicEraserTheater(progress: workProgress, status: status)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: isWorking)
        .navigationTitle("Magischer Radierer")
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(isPresented: $showLibrary, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .alert("Hinweis", isPresented: Binding(
            get: { status.hasPrefix("Fehler:") },
            set: { _ in }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(status)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                maskPulse = true
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nur der bemalte Bereich ändert sich")
                .font(.subheadline.weight(.semibold))
            Text("Standard: Entfernen. Markieren → fertig — oder eigene Anweisung tippen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(status)
                .font(.caption)
                .foregroundStyle(NOCOAITheme.accent)
                .contentTransition(.opacity)
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
                    onPaintingChange: { painting in
                        isPainting = painting
                    }
                )
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(8)
                    .overlay {
                        if canvas.hasPaint {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(
                                    AngularGradient(
                                        colors: rainbowColors,
                                        center: .center
                                    ).opacity(maskPulse ? 0.7 : 0.35),
                                    lineWidth: 2.5
                                )
                                .padding(8)
                                .allowsHitTesting(false)
                        }
                    }
            } else {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                AngularGradient(
                                    colors: rainbowColors,
                                    center: .center
                                )
                            )
                            .frame(width: 78, height: 78)
                            .blur(radius: 16)
                            .opacity(0.75)
                        Image(systemName: "paintbrush.pointed.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(NOCOAITheme.accent)
                            .symbolEffect(.pulse, options: .repeating)
                    }
                    Text("Foto aus der Galerie wählen")
                        .font(.subheadline.weight(.medium))
                    Button {
                        HapticService.open()
                        showLibrary = true
                    } label: {
                        Label("Galerie", systemImage: "photo.on.rectangle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(40)
            }
        }
        .frame(minHeight: 340)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(NOCOAITheme.glowPrimary.opacity(0.35), lineWidth: 1)
        )
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Pinsel")
                    .font(.caption.weight(.semibold))
                Slider(value: $brushSize, in: 12...72)
                Text("\(Int(brushSize))")
                    .font(.caption.monospacedDigit())
                    .frame(width: 28, alignment: .trailing)
            }
            HStack(spacing: 10) {
                Button {
                    HapticService.light()
                    showLibrary = true
                } label: {
                    Label("Anderes Foto", systemImage: "photo")
                }
                .buttonStyle(.bordered)
                .disabled(isWorking)

                Button {
                    HapticService.soft()
                    canvas.clear()
                } label: {
                    Label("Maske löschen", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(sourceImage == nil || isWorking)
            }
        }
    }

    private var presetRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aktion")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Preset.allCases) { p in
                    Button {
                        HapticService.selection()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            preset = p
                            if p != .custom {
                                instruction = p.defaultText
                            } else if instruction == Preset.erase.defaultText || instruction == Preset.replace.defaultText {
                                instruction = ""
                            }
                            if p == .custom || p == .replace {
                                promptFocused = true
                            }
                        }
                    } label: {
                        Label(p.title, systemImage: p.systemImage)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity)
                            .background {
                                if preset == p {
                                    Capsule(style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.4, green: 0.55, blue: 1),
                                                    Color(red: 0.75, green: 0.4, blue: 0.95)
                                                ],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                } else {
                                    Capsule(style: .continuous)
                                        .fill(Color.primary.opacity(0.06))
                                }
                            }
                            .foregroundStyle(preset == p ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preset == .erase ? "Anweisung (Standard: Entfernen)" : "Anweisung")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(
                preset == .replace
                    ? "z. B. blauer Himmel / rote Haare…"
                    : "z. B. entferne das Auto…",
                text: $instruction,
                axis: .vertical
            )
            .lineLimit(2...4)
            .focused($promptFocused)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                promptFocused
                                    ? NOCOAITheme.glowPrimary.opacity(0.55)
                                    : Color.clear,
                                lineWidth: 1.2
                            )
                    )
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
                Text(isWorking ? "Magie läuft…" : (preset == .erase ? "Entfernen" : "Magisch bearbeiten"))
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: rainbowColors.dropLast(),
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .foregroundStyle(.white)
            .shadow(color: Color(red: 0.45, green: 0.4, blue: 1).opacity(0.45), radius: 16, y: 6)
        }
        .disabled(isWorking || sourceImage == nil || effectivePrompt.isEmpty)
        .opacity(sourceImage == nil ? 0.5 : 1)
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
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: NOCOAITheme.glowPrimary.opacity(0.35), radius: 18)
                .scaleEffect(revealResult ? 1 : 0.92)
                .opacity(revealResult ? 1 : 0)
            Button {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                HapticService.success()
                status = "In Fotos gespeichert"
            } label: {
                Label("In Fotos speichern", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        if let data = await ChatPhotoLoader.loadJPEG(from: item),
           let ui = UIImage(data: data) {
            sourceImage = ui
            resultImage = nil
            revealResult = false
            canvas.clear()
            status = "Bereich bemalen — Standard: Entfernen"
            HapticService.success()
        } else {
            status = "Fehler: Foto konnte nicht geladen werden"
            HapticService.error()
        }
        photoItem = nil
    }

    private func runEraser() async {
        guard let sourceImage else {
            status = "Fehler: Kein Foto"
            return
        }
        guard connection.isOnline else {
            status = "Fehler: Nicht mit PC verbunden"
            return
        }
        let prompt = effectivePrompt
        guard !prompt.isEmpty else { return }

        guard canvas.exportMaskPNG(matching: sourceImage) != nil,
              canvas.hasPaint else {
            status = "Fehler: Bitte zuerst einen Bereich bemalen"
            HapticService.warning()
            return
        }

        let working = sourceImage.resizedToFit(maxSide: 512)
        guard let jpeg = working.jpegData(compressionQuality: 0.9),
              let maskForSD = canvas.exportMaskPNG(matching: working) else { return }

        isWorking = true
        workProgress = 0.08
        promptFocused = false
        status = "Nur Maske wird bearbeitet…"
        HapticService.medium()

        let progressTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 260_000_000)
                await MainActor.run {
                    if workProgress < 0.88 {
                        workProgress = min(0.88, workProgress + Double.random(in: 0.03...0.07))
                        if workProgress < 0.35 {
                            status = "Maske lesen…"
                        } else if workProgress < 0.65 {
                            status = preset == .erase ? "Entfernen auf dem PC…" : "Magie auf dem PC…"
                        } else {
                            status = "Nur Detail neu zeichnen…"
                        }
                    }
                }
            }
        }

        let sdPrompt = ImageAttachIntent.editPrompt(from: prompt)
        let denoise = ImageAttachIntent.denoising(for: prompt)

        do {
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
                } else {
                    isWorking = false
                    status = "Fehler: Bild konnte nicht gelesen werden"
                    HapticService.error()
                }
            } else if result.resolvedPath != nil {
                isWorking = false
                status = "Fertig — siehe Galerie"
                HapticService.success()
            } else {
                isWorking = false
                status = "Fehler: Keine Bilddaten vom PC"
                HapticService.error()
            }
        } catch {
            progressTask.cancel()
            isWorking = false
            status = "Fehler: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
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
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)

            VStack(spacing: 22) {
                ZStack {
                    AngularGradient(colors: rainbow, center: .center)
                        .frame(width: 240, height: 240)
                        .blur(radius: 42)
                        .opacity(pulse ? 0.65 : 0.35)
                        .scaleEffect(pulse ? 1.12 : 0.9)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .blendMode(.plusLighter)

                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(rainbow[i * 2].opacity(ripple ? 0.0 : 0.4 - Double(i) * 0.1), lineWidth: 2)
                            .frame(width: 95 + CGFloat(i * 40), height: 95 + CGFloat(i * 40))
                            .scaleEffect(ripple ? 1.4 : 0.88)
                    }

                    Circle()
                        .stroke(
                            AngularGradient(colors: rainbow, center: .center),
                            lineWidth: 5
                        )
                        .frame(width: 112, height: 112)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .shadow(color: Color(red: 0.7, green: 0.4, blue: 1).opacity(0.8), radius: 16)

                    Circle()
                        .trim(from: 0, to: max(0.04, min(progress, 1)))
                        .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .frame(width: 92, height: 92)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.3), value: progress)

                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, options: .repeating)
                        .scaleEffect(pulse ? 1.1 : 0.92)

                    ForEach(0..<10, id: \.self) { i in
                        Image(systemName: "sparkle")
                            .font(.system(size: CGFloat(6 + i % 4 * 2), weight: .bold))
                            .foregroundStyle(rainbow[i % (rainbow.count - 1)].opacity(spark ? 1 : 0.2))
                            .offset(
                                x: cos(Double(i) / 10 * .pi * 2) * (spark ? 82 : 66),
                                y: sin(Double(i) / 10 * .pi * 2) * (spark ? 82 : 66)
                            )
                    }
                }
                .frame(height: 240)
                .hueRotation(.degrees(hue ? 28 : -12))

                VStack(spacing: 8) {
                    Text("\(pct)%")
                        .font(.title.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(status)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .multilineTextAlignment(.center)
                    Text("Nur markierter Bereich")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .background(
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.88))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(
                                    AngularGradient(colors: rainbow, center: .center),
                                    lineWidth: 1.4
                                )
                        )
                )
            }
            .padding(24)
        }
        .allowsHitTesting(true)
        .onAppear {
            withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { spark = true }
            withAnimation(.easeOut(duration: 1.7).repeatForever(autoreverses: false)) { ripple = true }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { hue = true }
            HapticService.medium()
        }
    }
}

// MARK: - Canvas

final class MaskCanvasController: ObservableObject {
    weak var drawView: MaskDrawView?
    var hasPaint: Bool { drawView?.hasPaint == true }

    func clear() { drawView?.clear() }

    func exportMaskPNG(matching image: UIImage) -> Data? {
        drawView?.exportMaskPNG(targetSize: image.size)
    }
}

struct MaskPaintCanvas: UIViewRepresentable {
    let image: UIImage
    @ObservedObject var controller: MaskCanvasController
    var brushSize: CGFloat
    var onPaintingChange: ((Bool) -> Void)?

    func makeUIView(context: Context) -> MaskDrawView {
        let v = MaskDrawView(image: image)
        v.brushSize = brushSize
        v.onPaintingChange = onPaintingChange
        controller.drawView = v
        return v
    }

    func updateUIView(_ uiView: MaskDrawView, context: Context) {
        uiView.brushSize = brushSize
        uiView.onPaintingChange = onPaintingChange
        if uiView.baseImage.size != image.size {
            uiView.setBaseImage(image)
        }
        controller.drawView = uiView
    }
}

final class MaskDrawView: UIView {
    private(set) var baseImage: UIImage
    private var maskLayer = CAShapeLayer()
    private var path = UIBezierPath()
    private(set) var hasPaint = false
    var brushSize: CGFloat = 36
    var onPaintingChange: ((Bool) -> Void)?
    private var strokeHue: CGFloat = 0.55

    init(image: UIImage) {
        self.baseImage = image
        super.init(frame: .zero)
        isMultipleTouchEnabled = false
        backgroundColor = .black
        contentMode = .scaleAspectFit
        // Rainbow Intelligence stroke (not flat red/pink)
        maskLayer.strokeColor = UIColor(hue: strokeHue, saturation: 0.9, brightness: 1, alpha: 0.72).cgColor
        maskLayer.fillColor = UIColor.clear.cgColor
        maskLayer.lineCap = .round
        maskLayer.lineJoin = .round
        layer.addSublayer(maskLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setBaseImage(_ image: UIImage) {
        baseImage = image
        clear()
        setNeedsDisplay()
    }

    func clear() {
        path = UIBezierPath()
        maskLayer.path = nil
        hasPaint = false
    }

    override func draw(_ rect: CGRect) {
        let drawRect = aspectFitRect(for: baseImage.size, in: bounds)
        baseImage.draw(in: drawRect)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        maskLayer.frame = bounds
        setNeedsDisplay()
    }

    private func setParentScrollEnabled(_ enabled: Bool) {
        var view: UIView? = self
        while let current = view {
            if let scroll = current as? UIScrollView {
                scroll.isScrollEnabled = enabled
            }
            view = current.superview
        }
        onPaintingChange?(!enabled)
    }

    private func advanceRainbowStroke() {
        strokeHue = strokeHue + 0.035
        if strokeHue > 1 { strokeHue -= 1 }
        maskLayer.strokeColor = UIColor(hue: strokeHue, saturation: 0.92, brightness: 1, alpha: 0.75).cgColor
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let p = touches.first?.location(in: self) else { return }
        setParentScrollEnabled(false)
        path.move(to: p)
        path.lineWidth = brushSize
        hasPaint = true
        advanceRainbowStroke()
        HapticService.whisper()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let p = touches.first?.location(in: self) else { return }
        path.addLine(to: p)
        path.lineWidth = brushSize
        maskLayer.path = path.cgPath
        maskLayer.lineWidth = brushSize
        advanceRainbowStroke()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        setParentScrollEnabled(true)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        setParentScrollEnabled(true)
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
            UIColor.white.setStroke()
            let exportPath = path.copy() as? UIBezierPath ?? path
            exportPath.lineWidth = brushSize
            exportPath.lineCapStyle = .round
            exportPath.lineJoinStyle = .round
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
