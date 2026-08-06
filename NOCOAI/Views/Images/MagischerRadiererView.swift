import PhotosUI
import SwiftUI
import UIKit

/// Magischer AI-Radierer: Foto wählen, Bereich bemalen, Anweisung tippen → SD Inpaint.
struct MagischerRadiererView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var photoItem: PhotosPickerItem?
    @State private var sourceImage: UIImage?
    @State private var brushSize: CGFloat = 36
    @State private var instruction = ""
    @State private var isWorking = false
    @State private var workProgress: Double = 0
    @State private var status = "1 Foto · 2 bemalen · 3 Anweisung · 4 Magisch"
    @State private var resultImage: UIImage?
    @State private var canvas = MaskCanvasController()
    @State private var showLibrary = false
    @State private var revealResult = false
    @State private var maskPulse = false
    @FocusState private var promptFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                canvasCard
                controls
                promptCard
                actionButtons
                if let resultImage {
                    resultCard(resultImage)
                }
            }
            .padding(20)
        }
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
            Text("Bereich bemalen → KI ändert genau dort")
                .font(.subheadline.weight(.semibold))
            Text("Pinsel = Maske. Dann tippen, was passieren soll — z. B. „entferne den Baum“ oder „Himmel dramatischer“.")
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
                MaskPaintCanvas(image: sourceImage, controller: canvas, brushSize: brushSize)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(8)
                    .overlay {
                        if canvas.hasPaint {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(
                                    Color(red: 0.95, green: 0.4, blue: 0.75).opacity(maskPulse ? 0.55 : 0.2),
                                    lineWidth: 2
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
                                    colors: [
                                        Color(red: 0.4, green: 0.7, blue: 1),
                                        Color(red: 0.75, green: 0.4, blue: 1),
                                        Color(red: 0.95, green: 0.5, blue: 0.75),
                                        Color(red: 0.4, green: 0.7, blue: 1)
                                    ],
                                    center: .center
                                )
                            )
                            .frame(width: 72, height: 72)
                            .blur(radius: 18)
                            .opacity(0.7)
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

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Was soll passieren?")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("z. B. entferne das Auto / mach Haare rot…", text: $instruction, axis: .vertical)
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
                Text(isWorking ? "Magie läuft…" : "Magisch bearbeiten")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.35, green: 0.55, blue: 1),
                        Color(red: 0.7, green: 0.4, blue: 0.95),
                        Color(red: 0.95, green: 0.45, blue: 0.7)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .foregroundStyle(.white)
            .shadow(color: Color(red: 0.45, green: 0.4, blue: 1).opacity(0.45), radius: 16, y: 6)
        }
        .disabled(isWorking || sourceImage == nil || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(sourceImage == nil ? 0.5 : 1)
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
                .overlay {
                    if revealResult {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.6),
                                        Color(red: 0.6, green: 0.5, blue: 1).opacity(0.4),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                            .allowsHitTesting(false)
                    }
                }
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
            status = "Bereich bemalen, dann Anweisung tippen"
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
        let prompt = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        guard let maskPNG = canvas.exportMaskPNG(matching: sourceImage),
              canvas.hasPaint else {
            status = "Fehler: Bitte zuerst einen Bereich bemalen"
            HapticService.warning()
            return
        }
        _ = maskPNG
        // Match SD working size (512) for reliable mask alignment
        let working = sourceImage.resizedToFit(maxSide: 512)
        guard let jpeg = working.jpegData(compressionQuality: 0.9),
              let maskForSD = canvas.exportMaskPNG(matching: working) else { return }

        isWorking = true
        workProgress = 0.08
        promptFocused = false
        status = "Maske wird gelesen…"
        HapticService.medium()

        let progressTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 280_000_000)
                await MainActor.run {
                    if workProgress < 0.88 {
                        workProgress = min(0.88, workProgress + Double.random(in: 0.03...0.07))
                        if workProgress < 0.35 {
                            status = "Pinselspur analysieren…"
                        } else if workProgress < 0.65 {
                            status = "Magie auf dem PC…"
                        } else {
                            status = "Pixel neu zeichnen…"
                        }
                    }
                }
            }
        }

        do {
            let result = try await connection.images.runInpaint(
                prompt: ImageAttachIntent.editPrompt(from: prompt),
                imageJPEG: jpeg,
                maskPNG: maskForSD
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
                    try? await Task.sleep(nanoseconds: 350_000_000)
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

// MARK: - Apple Intelligence–style eraser theater

private struct MagicEraserTheater: View {
    var progress: Double
    var status: String

    @State private var spin = false
    @State private var pulse = false
    @State private var spark = false
    @State private var ripple = false

    private var pct: Int { Int((min(max(progress, 0), 1) * 100).rounded()) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)

            VStack(spacing: 22) {
                ZStack {
                    // Aurora blobs
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(blob(i).opacity(0.5))
                            .frame(width: 160 + CGFloat(i * 28), height: 160 + CGFloat(i * 28))
                            .blur(radius: 34)
                            .offset(
                                x: pulse ? CGFloat(20 - i * 10) : CGFloat(-18 + i * 8),
                                y: pulse ? CGFloat(-14 + i * 5) : CGFloat(12 - i * 4)
                            )
                            .blendMode(.plusLighter)
                    }

                    // Ripple rings
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(Color.white.opacity(ripple ? 0.0 : 0.35 - Double(i) * 0.1), lineWidth: 1.5)
                            .frame(width: 90 + CGFloat(i * 36), height: 90 + CGFloat(i * 36))
                            .scaleEffect(ripple ? 1.35 : 0.85)
                    }

                    // Rotating angular ring
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    Color(red: 0.4, green: 0.8, blue: 1),
                                    Color(red: 0.85, green: 0.4, blue: 1),
                                    Color(red: 0.95, green: 0.55, blue: 0.75),
                                    Color(red: 0.4, green: 0.9, blue: 0.85),
                                    Color(red: 0.4, green: 0.8, blue: 1)
                                ],
                                center: .center
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 108, height: 108)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .shadow(color: Color(red: 0.55, green: 0.4, blue: 1).opacity(0.7), radius: 14)

                    // Progress arc
                    Circle()
                        .trim(from: 0, to: max(0.04, min(progress, 1)))
                        .stroke(
                            Color.white.opacity(0.85),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 88, height: 88)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.35), value: progress)

                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, options: .repeating)
                        .scaleEffect(pulse ? 1.08 : 0.94)

                    // Sparkles
                    ForEach(0..<8, id: \.self) { i in
                        Image(systemName: "sparkle")
                            .font(.system(size: CGFloat(7 + i % 3 * 2), weight: .bold))
                            .foregroundStyle(.white.opacity(spark ? 0.95 : 0.2))
                            .offset(
                                x: cos(Double(i) / 8 * .pi * 2) * (spark ? 78 : 64),
                                y: sin(Double(i) / 8 * .pi * 2) * (spark ? 78 : 64)
                            )
                    }
                }
                .frame(height: 220)

                VStack(spacing: 8) {
                    Text("\(pct)%")
                        .font(.title.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(status)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                    Text("Magischer Radierer")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .background(
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.85))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                )
            }
            .padding(24)
        }
        .allowsHitTesting(true)
        .onAppear {
            withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { spark = true }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { ripple = true }
        }
    }

    private func blob(_ i: Int) -> Color {
        switch i {
        case 0: return Color(red: 0.35, green: 0.7, blue: 1)
        case 1: return Color(red: 0.7, green: 0.4, blue: 1)
        default: return Color(red: 0.95, green: 0.5, blue: 0.75)
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

    func makeUIView(context: Context) -> MaskDrawView {
        let v = MaskDrawView(image: image)
        v.brushSize = brushSize
        controller.drawView = v
        return v
    }

    func updateUIView(_ uiView: MaskDrawView, context: Context) {
        uiView.brushSize = brushSize
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

    init(image: UIImage) {
        self.baseImage = image
        super.init(frame: .zero)
        isMultipleTouchEnabled = false
        backgroundColor = .black
        contentMode = .scaleAspectFit
        maskLayer.strokeColor = UIColor.systemPink.withAlphaComponent(0.55).cgColor
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

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let p = touches.first?.location(in: self) else { return }
        path.move(to: p)
        path.lineWidth = brushSize
        hasPaint = true
        HapticService.whisper()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let p = touches.first?.location(in: self) else { return }
        path.addLine(to: p)
        path.lineWidth = brushSize
        maskLayer.path = path.cgPath
        maskLayer.lineWidth = brushSize
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
