import SwiftUI

struct RootView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if connection.isPaired {
                MainTabView()
            } else {
                PairingView()
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: connection.isPaired)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                connection.onForeground()
            case .background, .inactive:
                connection.onBackground()
            @unknown default:
                break
            }
        }
    }
}
