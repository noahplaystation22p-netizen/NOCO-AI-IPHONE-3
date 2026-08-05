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
    @State private var status = "Foto wählen, Bereich bemalen, dann Anweisung tippen"
    @State private var resultImage: UIImage?
    @State private var canvas = MaskCanvasController()
    @State private var showLibrary = false
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bereich bemalen → KI ändert genau dort")
                .font(.subheadline.weight(.semibold))
            Text("Weiß/Magenta = wird bearbeitet. Rest bleibt. z. B. „entferne den Baum“ oder „mach den Himmel dramatischer“.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(status)
                .font(.caption)
                .foregroundStyle(NOCOAITheme.accent)
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
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "paintbrush.pointed.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(NOCOAITheme.accent)
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
            Text("Anweisung")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("z. B. entferne das Auto / mach Haare rot…", text: $instruction, axis: .vertical)
                .lineLimit(2...4)
                .focused($promptFocused)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
        }
    }

    private var actionButtons: some View {
        Button {
            Task { await runEraser() }
        } label: {
            HStack {
                if isWorking { ProgressView().tint(.white) }
                Text(isWorking ? "KI arbeitet…" : "Magisch bearbeiten")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.35, green: 0.55, blue: 1), Color(red: 0.7, green: 0.4, blue: 0.95)],
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
        // Match SD working size (512) for reliable mask alignment
        let working = sourceImage.resizedToFit(maxSide: 512)
        guard let jpeg = working.jpegData(compressionQuality: 0.9),
              let maskForSD = canvas.exportMaskPNG(matching: working) else { return }

        isWorking = true
        promptFocused = false
        status = "Magischer Radierer läuft auf dem PC…"
        HapticService.medium()

        do {
            let result = try await connection.images.runInpaint(
                prompt: ImageAttachIntent.editPrompt(from: prompt),
                imageJPEG: jpeg,
                maskPNG: maskForSD
            )
            if let b64 = result.imageBase64 {
                let cleaned = b64
                    .replacingOccurrences(of: "\n", with: "")
                    .replacingOccurrences(of: "data:image/png;base64,", with: "")
                    .replacingOccurrences(of: "data:image/jpeg;base64,", with: "")
                if let data = Data(base64Encoded: cleaned), let ui = UIImage(data: data) {
                    resultImage = ui
                    status = "Fertig ✨"
                    HapticService.success()
                    connection.images.ingestEditedImage(
                        prompt: prompt,
                        localData: data,
                        path: result.resolvedPath
                    )
                } else {
                    status = "Fehler: Bild konnte nicht gelesen werden"
                    HapticService.error()
                }
            } else if let path = result.resolvedPath,
                      let url = URL(string: path) ?? nil {
                status = "Fertig — siehe Galerie"
                HapticService.success()
                _ = url
            } else {
                status = "Fehler: Keine Bilddaten vom PC"
                HapticService.error()
            }
        } catch {
            status = "Fehler: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            HapticService.error()
        }
        isWorking = false
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
