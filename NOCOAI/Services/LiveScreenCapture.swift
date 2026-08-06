import CoreMedia
import Foundation
import ReplayKit
import UIKit

/// Pluggable capture — Broadcast Extension / Camera / AR plug in without rewriting the session.
protocol LiveScreenCaptureProviding: AnyObject {
    var kind: LiveScreenCaptureKind { get }
    func prepare() async throws
    func stop()
}

/// In-app ReplayKit capture of the NOCO window (official API, user-started).
@MainActor
final class LiveScreenInAppReplayCapture: NSObject, LiveScreenCaptureProviding {
    let kind: LiveScreenCaptureKind = .inAppReplay

    private var latestSample: UIImage?
    private var isCapturing = false
    private var lastEmitAt: Date = .distantPast
    var onFrame: ((UIImage) -> Void)?

    func prepare() async throws {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            throw LiveScreenError.captureUnavailable
        }
        guard !isCapturing else { return }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            recorder.isMicrophoneEnabled = false
            recorder.startCapture { [weak self] sample, bufferType, error in
                if error != nil { return }
                guard bufferType == .video else { return }
                guard let image = Self.image(from: sample) else { return }
                Task { @MainActor in
                    guard let self else { return }
                    self.latestSample = image
                    let now = Date()
                    // ~2.5 fps preview — keeps UI smooth without burning CPU
                    guard now.timeIntervalSince(self.lastEmitAt) >= 0.4 else { return }
                    self.lastEmitAt = now
                    self.onFrame?(image)
                }
            } completionHandler: { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    Task { @MainActor in
                        self.isCapturing = true
                    }
                    cont.resume()
                }
            }
        }
    }

    func stop() {
        guard isCapturing else { return }
        RPScreenRecorder.shared().stopCapture { _ in }
        isCapturing = false
        latestSample = nil
    }

    func currentFrame() -> UIImage? { latestSample }

    private static func image(from sample: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

enum LiveScreenError: LocalizedError {
    case notConsented
    case notActive
    case noFrame
    case offline
    case captureUnavailable
    case processing

    var errorDescription: String? {
        switch self {
        case .notConsented: return "Live Screen braucht deine Zustimmung zur Bildschirmhilfe."
        case .notActive: return "Live Screen ist nicht aktiv."
        case .noFrame: return "Kein Bildschirmbild vorhanden — Screenshot teilen oder Aufnahme starten."
        case .offline: return "NOCO Companion ist offline."
        case .captureUnavailable: return "Bildschirmaufnahme ist auf diesem Gerät nicht verfügbar."
        case .processing: return "Analyse läuft noch."
        }
    }
}
