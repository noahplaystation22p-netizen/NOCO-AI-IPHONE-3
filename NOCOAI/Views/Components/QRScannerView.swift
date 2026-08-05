import AVFoundation
import SwiftUI

struct QRScannerView: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pixelPhase: PixelSpherePhase = .idle
    @State private var foundBanner = false

    var body: some View {
        ZStack {
            QRScannerRepresentable(
                onLocking: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        pixelPhase = .locking
                    }
                    HapticService.soft()
                },
                onCode: { code in
                    HapticService.success()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
                        pixelPhase = .success
                        foundBanner = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                        onCode(code)
                        dismiss()
                    }
                }
            )
            .ignoresSafeArea()

            // Pixel ring around the clear scan window (no solid ball)
            IntelligenceScanAura(phase: pixelPhase)
                .opacity(0.92)

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            Color(red: 0.4, green: 0.85, blue: 1).opacity(pixelPhase == .success ? 1 : 0.9),
                            Color(red: 0.75, green: 0.4, blue: 1).opacity(0.55),
                            Color(red: 1.0, green: 0.45, blue: 0.75).opacity(0.7),
                            Color(red: 0.4, green: 0.85, blue: 1).opacity(0.9)
                        ],
                        center: .center
                    ),
                    lineWidth: pixelPhase == .success ? 3.5 : 2.5
                )
                .frame(width: 236, height: 236)
                .shadow(color: Color(red: 0.45, green: 0.7, blue: 1).opacity(pixelPhase == .success ? 0.85 : 0.45), radius: pixelPhase == .success ? 28 : 18)
                .scaleEffect(pixelPhase == .success ? 1.06 : 1)

            if foundBanner {
                VStack {
                    Spacer()
                    Label("Verbunden — Pixel synchronisieren…", systemImage: "checkmark.seal.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 36)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            } else {
                VStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Text("QR vom PC in den Rahmen halten")
                            .font(.subheadline.weight(.semibold))
                        Text("Sobald der Code erkannt wird, reagieren die Pixel.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct QRScannerRepresentable: UIViewControllerRepresentable {
    var onLocking: () -> Void
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onLocking = onLocking
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        uiViewController.onLocking = onLocking
        uiViewController.onCode = onCode
    }
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onLocking: (() -> Void)?
    private let session = AVCaptureSession()
    private var didEmit = false
    private var didLockPulse = false
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) { session.addOutput(output) }
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        self.previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.stopRunning()
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue else { return }

        if !didLockPulse {
            didLockPulse = true
            onLocking?()
        }

        guard !didEmit else { return }
        didEmit = true
        session.stopRunning()
        onCode?(value)
    }
}
