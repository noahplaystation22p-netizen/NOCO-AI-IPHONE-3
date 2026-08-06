import ReplayKit
import UIKit
import CoreMedia

/// Broadcast Upload Extension — appears in Control Center screen recording picker.
/// Writes system screen frames into the App Group for NOCO Live Screen.
final class SampleHandler: RPBroadcastSampleHandler {
    private var lastWrite = Date.distantPast
    private let minInterval: TimeInterval = 0.45

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
        lastWrite = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent),
              let packed = SharedBroadcastFrameStore.jpegData(from: cgImage) else { return }
        _ = SharedBroadcastFrameStore.writeJPEG(packed.0, width: packed.1, height: packed.2)
    }
}
