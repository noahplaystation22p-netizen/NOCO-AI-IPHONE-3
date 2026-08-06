import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @State private var selectedTab = 0

    var body: some View {
        Group {
            switch selectedTab {
            case 0:
                ChatHubView()
            case 1:
                ImagesHubView()
            default:
                MoreView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !connection.hideMainTabBar {
                LiquidGlassTabBar(selectedTab: $selectedTab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.keyboard)
        .tint(NOCOAITheme.accent)
        .intelligenceSelectionFeedback(selectedTab)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: selectedTab)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: connection.hideMainTabBar)
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
