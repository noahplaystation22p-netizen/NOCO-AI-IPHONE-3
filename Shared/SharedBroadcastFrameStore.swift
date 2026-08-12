import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers

/// Shared App Group bridge between Broadcast Upload Extension and Live Screen.
enum SharedBroadcastFrameStore {
    static let appGroupId = "group.de.noco.nocoai"
    static let jpegName = "livescreen-latest.jpg"
    static let metaName = "livescreen-meta.json"
    static let preferredExtensionBundleId = "de.noco.nocoai.96R99M23VH.broadcast"

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }

    private static var jpegURL: URL? { containerURL?.appendingPathComponent(jpegName) }
    private static var metaURL: URL? { containerURL?.appendingPathComponent(metaName) }

    static func markBroadcastActive(_ active: Bool) {
        var meta = loadMeta()
        meta["active"] = active
        meta["updatedAt"] = Date().timeIntervalSince1970
        saveMeta(meta)
    }

    static var isBroadcastActive: Bool {
        (loadMeta()["active"] as? Bool) ?? false
    }

    static var lastUpdatedAt: Date? {
        guard let t = loadMeta()["updatedAt"] as? Double else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    @discardableResult
    static func writeJPEG(_ data: Data, width: Int, height: Int, hash: UInt64 = 0) -> Bool {
        guard let jpegURL, let metaURL else { return false }
        do {
            // Write JPEG first, then meta with matching bytes/time so the app never
            // sees a new image paired with stale meta (or vice versa).
            try data.write(to: jpegURL, options: .atomic)
            let meta: [String: Any] = [
                "active": true,
                "updatedAt": Date().timeIntervalSince1970,
                "width": width,
                "height": height,
                "bytes": data.count,
                "hash": hash
            ]
            let json = try JSONSerialization.data(withJSONObject: meta, options: [])
            try json.write(to: metaURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Fast 64-bit fingerprint for Broadcast extension (no Vision framework there).
    static func quickHash(data: Data, width: Int, height: Int) -> UInt64 {
        var h: UInt64 = 14695981039346656037
        let step = max(1, data.count / 64)
        var i = 0
        while i < data.count {
            h ^= UInt64(data[i])
            h &*= 1099511628211
            i += step
        }
        h ^= UInt64(width) &<< 32
        h ^= UInt64(height)
        return h
    }

    static func hamming64(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    static func readImage() -> UIImage? {
        readLatest()?.image
    }

    /// Latest frame + timestamp for change detection (Broadcast → Live Screen).
    static func readLatest() -> (image: UIImage, updatedAt: TimeInterval, bytes: Int)? {
        guard let jpegURL,
              FileManager.default.fileExists(atPath: jpegURL.path),
              let data = try? Data(contentsOf: jpegURL),
              let image = UIImage(data: data) else { return nil }
        let meta = loadMeta()
        let updated = (meta["updatedAt"] as? Double) ?? Date().timeIntervalSince1970
        let bytes = (meta["bytes"] as? Int) ?? data.count
        return (image, updated, bytes)
    }

    static func clear() {
        if let jpegURL { try? FileManager.default.removeItem(at: jpegURL) }
        markBroadcastActive(false)
    }

    private static func loadMeta() -> [String: Any] {
        guard let metaURL,
              let data = try? Data(contentsOf: metaURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    private static func saveMeta(_ meta: [String: Any]) {
        guard let metaURL,
              let data = try? JSONSerialization.data(withJSONObject: meta) else { return }
        try? data.write(to: metaURL, options: .atomic)
    }

    /// Compress a CGImage to JPEG for App Group transfer.
    static func jpegData(from cgImage: CGImage, maxSide: CGFloat = 1280, quality: CGFloat = 0.55) -> (Data, Int, Int)? {
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let scale = min(1, maxSide / max(w, h))
        let tw = max(1, Int((w * scale).rounded()))
        let th = max(1, Int((h * scale).rounded()))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: tw,
            height: th,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: tw, height: th))
        guard let scaled = ctx.makeImage() else { return nil }

        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return (data as Data, tw, th)
    }
}
