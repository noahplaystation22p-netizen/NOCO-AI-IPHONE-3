import AVFoundation
import Foundation
import UIKit
import UserNotifications

enum AppNotificationService {
    static let imageReadyId = "nocoai.image.ready"
    static let imageRunningId = "nocoai.image.running"

    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            return false
        }
    }

    static func notifyImageStarted(prompt: String) async {
        // Progress is shown via Live Activity / Dynamic Island — no "started" push.
        _ = prompt
    }

    static func notifyImageReady(prompt: String) async {
        guard await requestAuthorizationIfNeeded() else { return }

        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [imageRunningId])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [imageRunningId])

        let content = UNMutableNotificationContent()
        content.title = "Bildidee fertig ✨"
        content.body = prompt.isEmpty
            ? "Dein Bild ist bereit — tippe zum Öffnen."
            : "Fertig: \(String(prompt.prefix(100)))"
        content.sound = .default
        content.badge = NSNumber(value: 1)
        content.userInfo = ["screen": "images"]
        content.interruptionLevel = .timeSensitive
        // Extra banner even if the app is open (user asked for a clear "done" ping)
        if #available(iOS 15.0, *) {
            content.relevanceScore = 1.0
        }

        let request = UNNotificationRequest(
            identifier: "\(imageReadyId).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func notifyEraserReady(prompt: String) async {
        guard await requestAuthorizationIfNeeded() else { return }

        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [imageRunningId])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [imageRunningId])

        let content = UNMutableNotificationContent()
        content.title = "Magischer Radierer fertig ✨"
        content.body = prompt.isEmpty
            ? "Dein bearbeitetes Bild ist bereit."
            : "Fertig: \(String(prompt.prefix(100)))"
        content.sound = .default
        content.badge = NSNumber(value: 1)
        content.userInfo = ["screen": "images", "eraser": true]
        content.interruptionLevel = .timeSensitive
        if #available(iOS 15.0, *) {
            content.relevanceScore = 1.0
        }

        let request = UNNotificationRequest(
            identifier: "\(imageReadyId).eraser.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func notifyAgentReady(goal: String) async {
        guard await requestAuthorizationIfNeeded() else { return }
        let content = UNMutableNotificationContent()
        content.title = "NOCO Agent fertig"
        content.body = goal.isEmpty ? "Deine Aufgabe ist erledigt." : String(goal.prefix(120))
        content.sound = .default
        content.badge = NSNumber(value: 1)
        content.userInfo = ["screen": "agent"]
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(
            identifier: "nocoai.agent.ready.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func notifyAgentNeedsConfirm(goal: String) async {
        guard await requestAuthorizationIfNeeded() else { return }
        let content = UNMutableNotificationContent()
        content.title = "NOCO Agent wartet"
        content.body = goal.isEmpty
            ? "Eine Aktion braucht deine Freigabe."
            : "Freigabe nötig: \(String(goal.prefix(100)))"
        content.sound = .default
        content.userInfo = ["screen": "agent"]
        let request = UNNotificationRequest(
            identifier: "nocoai.agent.confirm.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func notifyImageFailed(_ message: String) async {
        guard await requestAuthorizationIfNeeded() else { return }
        guard UIApplication.shared.applicationState != .active else { return }

        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [imageRunningId])

        let content = UNMutableNotificationContent()
        content.title = "Bildidee fehlgeschlagen"
        content.body = message
        content.sound = .default
        content.userInfo = ["screen": "images"]

        let request = UNNotificationRequest(
            identifier: "\(imageReadyId).fail.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func clearRunningNotification() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [imageRunningId])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [imageRunningId])
    }

    static func clearBadge() {
        Task { @MainActor in
            try? await UNUserNotificationCenter.current().setBadgeCount(0)
        }
        UIApplication.shared.applicationIconBadgeNumber = 0
    }
}

/// Keeps the process alive while SD runs (minutes): background task + quiet audio (existing audio mode).
@MainActor
final class ImageBackgroundKeeper {
    static let shared = ImageBackgroundKeeper()

    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private var silentPlayer: AVAudioPlayer?

    func begin(reason: String = "NOCO Bildidee") {
        end(preserveAudioSession: true)
        bgTask = UIApplication.shared.beginBackgroundTask(withName: reason) { [weak self] in
            Task { @MainActor in self?.end(preserveAudioSession: true) }
        }
        // Don't steal Speak's playAndRecord session
        let cat = AVAudioSession.sharedInstance().category
        if cat != .playAndRecord {
            startSilentAudioIfPossible()
        }
    }

    func end(preserveAudioSession: Bool = false) {
        stopSilentAudio(deactivateSession: !preserveAudioSession)
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }

    private func startSilentAudioIfPossible() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true, options: [])
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("noco-keep.wav")
            if !FileManager.default.fileExists(atPath: url.path) {
                try Self.writeTinySilentWav(to: url)
            }
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0.01
            player.prepareToPlay()
            player.play()
            silentPlayer = player
        } catch {
            // Background task alone as fallback
        }
    }

    private func stopSilentAudio(deactivateSession: Bool) {
        silentPlayer?.stop()
        silentPlayer = nil
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private static func writeTinySilentWav(to url: URL) throws {
        let sampleRate: UInt32 = 8000
        let numSamples: UInt32 = 2000
        var data = Data()
        func appendU32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func appendU16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
        appendU32(36 + numSamples)
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45, 0x66, 0x6D, 0x74, 0x20])
        appendU32(16)
        appendU16(1)
        appendU16(1)
        appendU32(sampleRate)
        appendU32(sampleRate)
        appendU16(1)
        appendU16(8)
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61])
        appendU32(numSamples)
        data.append(Data(repeating: 128, count: Int(numSamples)))
        try data.write(to: url)
    }
}
