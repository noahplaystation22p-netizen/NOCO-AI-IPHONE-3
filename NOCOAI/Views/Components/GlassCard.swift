import SwiftUI

struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: Content
    @State private var shimmer = false

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
                                        NOCOAITheme.glowPrimary.opacity(scheme == .dark ? (shimmer ? 0.42 : 0.22) : (shimmer ? 0.28 : 0.14)),
                                        NOCOAITheme.glowAccent.opacity(0.16),
                                        NOCOAITheme.glowSecondary.opacity(0.14),
                                        NOCOAITheme.cardStroke(for: scheme)
                                    ],
                                    startPoint: shimmer ? .topLeading : .bottomTrailing,
                                    endPoint: shimmer ? .bottomTrailing : .topLeading
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: NOCOAITheme.glowPrimary.opacity(shimmer ? 0.16 : 0.08), radius: 22, y: 8)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 3.8).repeatForever(autoreverses: true)) {
                    shimmer = true
                }
            }
    }
}
