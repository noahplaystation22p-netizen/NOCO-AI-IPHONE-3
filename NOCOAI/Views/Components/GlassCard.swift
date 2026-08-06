import SwiftUI

struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                                        NOCOAITheme.glowPrimary.opacity(scheme == .dark ? (shimmer ? 0.38 : 0.22) : (shimmer ? 0.26 : 0.16)),
                                        NOCOAITheme.glowAccent.opacity(0.14),
                                        NOCOAITheme.glowSecondary.opacity(0.12),
                                        NOCOAITheme.cardStroke(for: scheme)
                                    ],
                                    startPoint: shimmer ? .topLeading : .bottomTrailing,
                                    endPoint: shimmer ? .bottomTrailing : .topLeading
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: NOCOAITheme.glowPrimary.opacity(shimmer ? 0.14 : 0.08), radius: 18, y: 8)
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true)) {
                    shimmer = true
                }
            }
    }
}
