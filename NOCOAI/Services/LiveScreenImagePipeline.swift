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

/// Lightweight scene-change detector — avoids uploading every Broadcast frame.
enum LiveScreenSceneDiff {
    /// 8×8 average-hash style fingerprint (64-bit).
    static func perceptualHash(of image: UIImage, grid: Int = 8) -> UInt64 {
        let side = CGFloat(grid)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let tiny = renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        guard let cg = tiny.cgImage,
              let data = cg.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return 0 }

        let bpp = max(cg.bitsPerPixel / 8, 1)
        let bytesPerRow = cg.bytesPerRow
        var luminances = [Double]()
        luminances.reserveCapacity(grid * grid)
        for y in 0..<grid {
            for x in 0..<grid {
                let offset = y * bytesPerRow + x * bpp
                let r = Double(ptr[offset])
                let g = Double(ptr[min(offset + 1, bytesPerRow - 1)])
                let b = Double(ptr[min(offset + 2, bytesPerRow - 1)])
                luminances.append(0.299 * r + 0.587 * g + 0.114 * b)
            }
        }
        let mean = luminances.reduce(0, +) / Double(max(luminances.count, 1))
        var hash: UInt64 = 0
        for (i, v) in luminances.enumerated() where i < 64 {
            if v >= mean {
                hash |= (1 as UInt64) << UInt64(i)
            }
        }
        return hash
    }

    static func hamming(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    /// True when the scene meaningfully changed (or first frame).
    static func isSignificant(previous: UInt64?, new: UInt64, threshold: Int = 10) -> Bool {
        guard let previous else { return true }
        return hamming(previous, new) >= threshold
    }

    static func ocrChanged(_ a: String, _ b: String, minDelta: Int = 24) -> Bool {
        let left = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = b.trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty, right.isEmpty { return false }
        if left.isEmpty != right.isEmpty { return true }
        if left == right { return false }
        // Cheap length / prefix check — enough for UI text swaps
        if abs(left.count - right.count) >= minDelta { return true }
        let n = min(80, min(left.count, right.count))
        guard n > 0 else { return true }
        return String(left.prefix(n)) != String(right.prefix(n))
    }
}
