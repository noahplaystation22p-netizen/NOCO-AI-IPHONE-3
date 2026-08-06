import SwiftUI

struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(scheme == .dark ? 0.06 : 0.35),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        NOCOAITheme.glowPrimary.opacity(scheme == .dark ? 0.28 : 0.18),
                                        NOCOAITheme.glowAccent.opacity(0.14),
                                        NOCOAITheme.glowSecondary.opacity(0.12),
                                        NOCOAITheme.cardStroke(for: scheme)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: NOCOAITheme.glowPrimary.opacity(0.1), radius: 18, y: 8)
            )
    }
}
