import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)

            ChatHubView()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(1)

            ImagesHubView()
                .tabItem { Label("Bilder", systemImage: "photo.artframe") }
                .tag(2)

            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.bar.fill") }
                .tag(3)

            MoreView()
                .tabItem { Label("Mehr", systemImage: "ellipsis.circle.fill") }
                .tag(4)
        }
        .tint(NOCOAITheme.accent)
    }
}
