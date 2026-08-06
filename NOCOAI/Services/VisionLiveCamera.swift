import AVFoundation
import Combine
import CoreMedia
import SwiftUI
import UIKit

/// Live camera feed + throttled still frames for Vision Live.
@MainActor
final class VisionLiveCameraController: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var latestFrame: UIImage?
    @Published var useFrontCamera = false

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "de.noco.visionlive.camera")
    private let photoOutput = AVCapturePhotoOutput()
    private var videoOutput: AVCaptureVideoDataOutput?
    private var lastSampleAt: Date = .distantPast
    private var onFrame: ((UIImage) -> Void)?

    func setFrameHandler(_ handler: @escaping (UIImage) -> Void) {
        onFrame = handler
    }

    func requestAccessAndStart() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            await start()
        case .notDetermined:
            let ok = await AVCaptureDevice.requestAccess(for: .video)
            if ok { await start() }
            else { permissionDenied = true }
        default:
            permissionDenied = true
        }
    }

    func start() async {
        permissionDenied = false
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                self.configureIfNeeded()
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                DispatchQueue.main.async {
                    self.isRunning = true
                    cont.resume()
                }
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }

    func flipCamera() async {
        useFrontCamera.toggle()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                self.session.beginConfiguration()
                for input in self.session.inputs {
                    self.session.removeInput(input)
                }
                self.addCameraInput()
                self.session.commitConfiguration()
                DispatchQueue.main.async { cont.resume() }
            }
        }
        HapticService.soft()
    }

    func captureStill() async -> UIImage? {
        if let latest = latestFrame { return latest }
        // Fallback: wait briefly for a sample
        try? await Task.sleep(nanoseconds: 200_000_000)
        return latestFrame
    }

    private var configured = false

    private func configureIfNeeded() {
        guard !configured else {
            // Still ensure input matches flip
            return
        }
        session.beginConfiguration()
        session.sessionPreset = .high
        addCameraInput()
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: sessionQueue)
        if session.canAddOutput(output) {
            session.addOutput(output)
            videoOutput = output
        }
        session.commitConfiguration()
        configured = true
    }

    private func addCameraInput() {
        let position: AVCaptureDevice.Position = useFrontCamera ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
    }
}

extension VisionLiveCameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let image = Self.image(from: sampleBuffer) else { return }
        Task { @MainActor in
            let now = Date()
            // ~3 fps preview samples for analysis pipeline
            guard now.timeIntervalSince(self.lastSampleAt) >= 0.33 else {
                self.latestFrame = image
                return
            }
            self.lastSampleAt = now
            self.latestFrame = image
            self.onFrame?(image)
        }
    }

    private nonisolated static func image(from sample: CMSampleBuffer) -> UIImage? {
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
        let ci = CIImage(cvPixelBuffer: buffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = context.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: .right)
    }
}

struct VisionLiveCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
