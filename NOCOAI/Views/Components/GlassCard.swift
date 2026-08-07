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
                                        Color.white.opacity(scheme == .dark ? 0.08 : 0.38),
                                        NOCORainbow.violet.opacity(scheme == .dark ? 0.04 : 0.03),
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
                                AngularGradient(
                                    colors: NOCORainbow.flow.map {
                                        $0.opacity(scheme == .dark
                                                   ? (shimmer ? 0.42 : 0.2)
                                                   : (shimmer ? 0.3 : 0.14))
                                    },
                                    center: .center
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: NOCORainbow.blue.opacity(shimmer ? 0.16 : 0.08), radius: 18, y: 8)
                    .shadow(color: NOCORainbow.violet.opacity(0.06), radius: 28, y: 12)
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true)) {
                    shimmer = true
                }
            }
    }
}
