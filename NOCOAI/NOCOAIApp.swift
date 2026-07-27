import SwiftUI

@main
struct NOCOAIApp: App {
    @StateObject private var connection = ConnectionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(connection)
        }
    }
}
