import SwiftUI

/// Floating liquid-glass capsule for Chat / Bilder / Studio.
struct LiquidGlassTabBar: View {
    @Binding var selectedTab: Int
    @Environment(\.colorScheme) private var scheme

    private let items: [(title: String, icon: String, selectedIcon: String)] = [
        ("Chat", "bubble.left.and.bubble.right", "sparkles"),
        ("Bilder", "paintbrush.pointed", "paintbrush.pointed.fill"),
        ("Studio", "square.grid.2x2", "square.grid.2x2.fill")
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                let selected = selectedTab == index
                Button {
                    guard selectedTab != index else { return }
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        selectedTab = index
                    }
                    HapticService.navigate()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: selected ? item.selectedIcon : item.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .symbolEffect(.bounce, value: selected)
                        Text(item.title)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.72))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if selected {
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            NOCOAITheme.glowPrimary.opacity(0.95),
                                            NOCOAITheme.glowSecondary.opacity(0.88),
                                            NOCOAITheme.glowAccent.opacity(0.9)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: NOCOAITheme.glowPrimary.opacity(0.35), radius: 10, y: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(scheme == .dark ? 0.28 : 0.55),
                                    NOCOAITheme.glowPrimary.opacity(0.35),
                                    Color.white.opacity(scheme == .dark ? 0.12 : 0.25)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.14), radius: 22, y: 10)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
    }
}
