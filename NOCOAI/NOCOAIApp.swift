import SwiftUI
import UserNotifications
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if let shortcut = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            NOCOQuickActionRouter.enqueue(shortcut.type)
        }
        return true
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        NOCOQuickActionRouter.enqueue(shortcutItem.type)
        NotificationCenter.default.post(name: .nocoQuickAction, object: shortcutItem.type)
        completionHandler(true)
    }

    // Show banner even if app is briefly in foreground when generation finishes
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        if (info["screen"] as? String) == "images" {
            NotificationCenter.default.post(name: .nocoOpenImages, object: nil)
        }
        if (info["screen"] as? String) == "agent" {
            NotificationCenter.default.post(name: .nocoOpenAgent, object: nil)
        }
    }
}

enum NOCOQuickActionRouter {
    private static let pendingKey = "nocoai.pendingQuickAction"

    static func enqueue(_ type: String) {
        UserDefaults.standard.set(type, forKey: pendingKey)
    }

    static func consume() -> String? {
        let value = UserDefaults.standard.string(forKey: pendingKey)
        UserDefaults.standard.removeObject(forKey: pendingKey)
        return value
    }
}

extension Notification.Name {
    static let nocoOpenImages = Notification.Name("nocoai.openImages")
    static let nocoOpenAgent = Notification.Name("nocoai.openAgent")
    static let nocoQuickAction = Notification.Name("nocoai.quickAction")
}

@main
struct NOCOAIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var connection = ConnectionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(connection)
                .onOpenURL { url in
                    connection.handleIncomingURL(url)
                }
                .onReceive(NotificationCenter.default.publisher(for: .nocoOpenImages)) { _ in
                    connection.openImagesTab()
                }
                .onReceive(NotificationCenter.default.publisher(for: .nocoOpenAgent)) { _ in
                    connection.pendingTab = 2
                    connection.pendingOpenAgent = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .nocoStartSpeak)) { _ in
                    connection.launchSpeakFromShortcut()
                }
                .onReceive(NotificationCenter.default.publisher(for: .nocoStopSpeak)) { _ in
                    connection.stopSpeakFromShortcut()
                }
                .onReceive(NotificationCenter.default.publisher(for: .nocoOpenImagesPrompt)) { note in
                    let prompt = note.userInfo?["prompt"] as? String
                    connection.launchImages(prompt: prompt)
                }
                .onReceive(NotificationCenter.default.publisher(for: .nocoOpenAgentGoal)) { note in
                    let goal = note.userInfo?["goal"] as? String
                    connection.launchAgent(goal: goal)
                }
                .onReceive(NotificationCenter.default.publisher(for: .nocoAskChat)) { note in
                    if let draft = note.userInfo?["draft"] as? String {
                        connection.launchAsk(draft: draft)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .nocoOpenVisionLive)) { _ in
                    connection.launchVisionLive()
                }
                .onReceive(NotificationCenter.default.publisher(for: .nocoQuickAction)) { note in
                    if let type = note.object as? String {
                        connection.handleQuickAction(type)
                    }
                }
                .task {
                    // Cold start from Shortcuts / Siri / Quick Actions while app was killed
                    connection.consumePendingSystemLaunches()
                }
        }
    }
}
