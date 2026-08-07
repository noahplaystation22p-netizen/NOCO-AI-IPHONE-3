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
                    Label("Bilder", systemImage: "paintbrush.pointed.fill")
                }
                .tag(1)

            MoreView()
                .tabItem {
                    Label("Studio", systemImage: selectedTab == 2 ? "square.grid.2x2.fill" : "square.grid.2x2")
                }
                .tag(2)
        }
        .tint(NOCOAITheme.accent)
        .intelligenceSelectionFeedback(selectedTab)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: selectedTab)
        .onChange(of: selectedTab) { _, _ in
            HapticService.navigate()
        }
        .onChange(of: connection.pendingTab) { _, tab in
            if let tab {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                    selectedTab = tab
                }
                connection.pendingTab = nil
                HapticService.open()
            }
        }
        .onAppear {
            HapticService.prepare()
            if let tab = connection.pendingTab {
                selectedTab = tab
                connection.pendingTab = nil
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { connection.speak.showSpeakUI },
            set: { connection.speak.showSpeakUI = $0 }
        )) {
            VoiceModeView()
                .environmentObject(connection)
                .onAppear { HapticService.open() }
        }
    }
}
