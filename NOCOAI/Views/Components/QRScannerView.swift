import AVFoundation
import SwiftUI

struct QRScannerView: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var flash = false

    var body: some View {
        ZStack {
            QRScannerRepresentable { code in
                HapticService.success()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    flash = true
                }
                onCode(code)
                dismiss()
            }
            .ignoresSafeArea()

            // Decorative pixel orb + scan frame (QR still does recognition)
            IntelligenceScanAura()
                .opacity(0.95)

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            Color(red: 0.4, green: 0.85, blue: 1).opacity(0.9),
                            Color(red: 0.75, green: 0.4, blue: 1).opacity(0.55),
                            Color(red: 1.0, green: 0.45, blue: 0.75).opacity(0.7),
                            Color(red: 0.4, green: 0.85, blue: 1).opacity(0.9)
                        ],
                        center: .center
                    ),
                    lineWidth: 2.5
                )
                .frame(width: 236, height: 236)
                .shadow(color: Color(red: 0.45, green: 0.7, blue: 1).opacity(0.55), radius: 22)
                .opacity(flash ? 0.2 : 1)

            VStack {
                Spacer()
                VStack(spacing: 8) {
                    Text("Pixel-Aura · QR scannen")
                        .font(.headline.weight(.semibold))
                    Text("Halte den Code vom PC in den Rahmen.\nDie bunte Kugel ist nur Deko — der QR verbindet dich.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var didEmit = false

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
        preview.frame = view.layer.bounds
        preview.videoGravity = .resizeAspectFill
        preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer.addSublayer(preview)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
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
        guard !didEmit,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue else { return }
        didEmit = true
        session.stopRunning()
        onCode?(value)
    }
}
