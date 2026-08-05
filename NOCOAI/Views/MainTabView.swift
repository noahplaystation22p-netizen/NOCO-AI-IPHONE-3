import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatHubView()
                .tabItem { Label("Chat", systemImage: "sparkles") }
                .tag(0)

            HomeView()
                .tabItem { Label("System", systemImage: "desktopcomputer") }
                .tag(1)

            MoreView()
                .tabItem { Label("Studio", systemImage: "square.grid.2x2.fill") }
                .tag(2)
        }
        .tint(NOCOAITheme.accent)
    }
}
