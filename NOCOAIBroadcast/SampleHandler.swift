import ReplayKit
import UIKit
import CoreMedia

/// Broadcast Upload Extension — appears in Control Center screen recording picker.
/// Writes system screen frames into the App Group for NOCO Live Screen.
/// Throttled + change-aware — never floods the main app at 60fps.
final class SampleHandler: RPBroadcastSampleHandler {
    private var lastWrite = Date.distantPast
    private var lastHash: UInt64 = 0
    private let minInterval: TimeInterval = 0.85

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        SharedBroadcastFrameStore.markBroadcastActive(true)
    }

    override func broadcastPaused() {
        SharedBroadcastFrameStore.markBroadcastActive(true)
    }

    override func broadcastResumed() {
        SharedBroadcastFrameStore.markBroadcastActive(true)
    }

    override func broadcastFinished() {
        SharedBroadcastFrameStore.markBroadcastActive(false)
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        let now = Date()
        guard now.timeIntervalSince(lastWrite) >= minInterval else { return }
        // Always advance throttle clock — static screens must not re-encode every 0.85s.
        lastWrite = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent),
              let packed = SharedBroadcastFrameStore.jpegData(from: cgImage) else { return }

        // Cheap hash from packed JPEG length + size — skip near-identical frames
        let hash = SharedBroadcastFrameStore.quickHash(data: packed.0, width: packed.1, height: packed.2)
        let changed = lastHash == 0 || SharedBroadcastFrameStore.hamming64(lastHash, hash) >= 6
        guard changed else { return }

        lastHash = hash
        _ = SharedBroadcastFrameStore.writeJPEG(packed.0, width: packed.1, height: packed.2, hash: hash)
    }
}
