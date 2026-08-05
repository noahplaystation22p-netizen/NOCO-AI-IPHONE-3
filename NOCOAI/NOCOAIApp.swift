import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
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
    }
}

extension Notification.Name {
    static let nocoOpenImages = Notification.Name("nocoai.openImages")
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
        }
    }
}
