import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatHubView()
                .tabItem {
                    Label("Chat", systemImage: selectedTab == 0 ? "sparkles" : "bubble.left.and.bubble.right")
                }
                .tag(0)

            ImagesHubView()
                .tabItem {
                    Label("Bildideen", systemImage: "paintbrush.pointed.fill")
                }
                .tag(1)

            MoreView()
                .tabItem {
                    Label("Studio", systemImage: "square.grid.2x2.fill")
                }
                .tag(2)
        }
        .tint(NOCOAITheme.accent)
        .sensoryFeedback(.selection, trigger: selectedTab)
        .onChange(of: selectedTab) { _, _ in
            HapticService.selection()
        }
        .fullScreenCover(isPresented: Binding(
            get: { connection.speak.showSpeakUI },
            set: { connection.speak.showSpeakUI = $0 }
        )) {
            VoiceModeView()
                .environmentObject(connection)
        }
    }
}
