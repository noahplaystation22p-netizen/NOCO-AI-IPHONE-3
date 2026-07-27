import SwiftUI

struct RootView: View {
    @EnvironmentObject private var connection: ConnectionStore

    var body: some View {
        Group {
            if connection.isPaired {
                MainTabView()
            } else {
                PairingView()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: connection.isPaired)
    }
}
