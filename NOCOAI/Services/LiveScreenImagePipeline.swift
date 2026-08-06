import UIKit
import Vision

enum LiveScreenImageOptimizer {
    /// Fast path for vision models — keep readable UI text, drop megapixel waste.
    static func jpeg(from image: UIImage, maxSide: CGFloat = 1280, quality: CGFloat = 0.78) -> Data? {
        let w = image.size.width * image.scale
        let h = image.size.height * image.scale
        let scale = min(1, maxSide / max(w, h))
        let target = CGSize(width: max(1, floor(w * scale)), height: max(1, floor(h * scale)))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    static func thumbnail(from jpeg: Data, maxSide: CGFloat = 160) -> Data? {
        guard let image = UIImage(data: jpeg) else { return nil }
        return self.jpeg(from: image, maxSide: maxSide, quality: 0.65)
    }
}

enum LiveScreenOCR {
    /// On-device text recognition — privacy-friendly context for the language model.
    static func recognizeText(in image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["de-DE", "en-US"]
            if #available(iOS 16.0, *) {
                request.automaticallyDetectsLanguage = true
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }
}
