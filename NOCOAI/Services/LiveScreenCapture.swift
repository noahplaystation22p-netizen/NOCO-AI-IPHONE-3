import CoreMedia
import Foundation
import ReplayKit
import SwiftUI
import UIKit

/// Pluggable capture — Broadcast Extension / Camera / AR plug in without rewriting the session.
protocol LiveScreenCaptureProviding: AnyObject {
    var kind: LiveScreenCaptureKind { get }
    func prepare() async throws
    nonisolated func stop()
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

    nonisolated func stop() {
        Task { @MainActor in
            guard self.isCapturing else { return }
            RPScreenRecorder.shared().stopCapture { _ in }
            self.isCapturing = false
            self.latestSample = nil
        }
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

/// System-wide screen broadcast via Control Center / RPSystemBroadcastPickerView.
/// Frames arrive from `NOCOAIBroadcast` SampleHandler through the App Group.
@MainActor
final class LiveScreenBroadcastCapture: LiveScreenCaptureProviding {
    let kind: LiveScreenCaptureKind = .broadcastExtension

    private var pollTask: Task<Void, Never>?
    private var lastUpdatedAt: TimeInterval = 0
    private var lastBytes: Int = -1
    var onFrame: ((UIImage) -> Void)?
    var onWaitingStatus: ((String) -> Void)?

    func prepare() async throws {
        // Cancel any previous poller synchronously — deferred stop() raced and killed new tasks.
        pollTask?.cancel()
        pollTask = nil
        lastUpdatedAt = 0
        lastBytes = -1
        onWaitingStatus?("Tippe den roten Übertragen-Button und wähle „NOCO Live Screen“")
        pollTask = Task { [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                if SharedBroadcastFrameStore.isBroadcastActive == false, ticks % 6 == 0 {
                    self?.onWaitingStatus?("Warte auf Bildschirmübertragung… (Kontrollzentrum oder roter Button)")
                }
                if let latest = SharedBroadcastFrameStore.readLatest() {
                    let changed = latest.updatedAt != self?.lastUpdatedAt || latest.bytes != self?.lastBytes
                    if changed {
                        self?.lastUpdatedAt = latest.updatedAt
                        self?.lastBytes = latest.bytes
                        self?.onFrame?(latest.image)
                        self?.onWaitingStatus?("Live — Frames vom System")
                    }
                }
                ticks += 1
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
    }

    nonisolated func stop() {
        Task { @MainActor [weak self] in
            self?.pollTask?.cancel()
            self?.pollTask = nil
            self?.lastUpdatedAt = 0
            self?.lastBytes = -1
        }
    }
}

/// System Broadcast picker — same path as holding Screen Recording in Control Center.
struct BroadcastPickerRepresentable: UIViewRepresentable {
    var preferredExtension: String = SharedBroadcastFrameStore.preferredExtensionBundleId
    var showsMicrophoneButton: Bool = false

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 48, height: 48))
        picker.preferredExtension = preferredExtension
        picker.showsMicrophoneButton = showsMicrophoneButton
        if let button = picker.subviews.compactMap({ $0 as? UIButton }).first {
            button.setImage(UIImage(systemName: "record.circle.fill"), for: .normal)
            button.tintColor = UIColor(red: 0.98, green: 0.35, blue: 0.32, alpha: 1)
            button.setTitle(nil, for: .normal)
        }
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        uiView.preferredExtension = preferredExtension
    }
}

enum LiveScreenError: LocalizedError {
    case notConsented
    case notActive
    case noFrame
    case offline
    case captureUnavailable
    case processing
    case permissionNeeded

    var errorDescription: String? {
        switch self {
        case .notConsented:
            return "Live Screen braucht deine Zustimmung zur Bildschirmhilfe."
        case .notActive:
            return "Live Screen ist nicht aktiv."
        case .noFrame:
            return "Kein Bildschirmbild — Übertragung starten oder Screenshot teilen."
        case .offline:
            return "NOCO Companion ist offline."
        case .captureUnavailable:
            return "Bildschirmaufnahme ist auf diesem Gerät nicht verfügbar."
        case .processing:
            return "Analyse läuft noch."
        case .permissionNeeded:
            return "Bildschirmübertragung fehlt. Tippe den roten Button und wähle „NOCO Live Screen“, oder erlaube Bildschirmaufnahme in den Einstellungen."
        }
    }
}
