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
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        NOCOAITheme.glowPrimary.opacity(scheme == .dark ? (shimmer ? 0.45 : 0.28) : (shimmer ? 0.32 : 0.18)),
                                        NOCOAITheme.glowSecondary.opacity(0.18),
                                        NOCOAITheme.cardStroke(for: scheme)
                                    ],
                                    startPoint: shimmer ? .topLeading : .bottomTrailing,
                                    endPoint: shimmer ? .bottomTrailing : .topLeading
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: NOCOAITheme.glowPrimary.opacity(shimmer ? 0.18 : 0.1), radius: 18, y: 6)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                    shimmer = true
                }
            }
    }
}
