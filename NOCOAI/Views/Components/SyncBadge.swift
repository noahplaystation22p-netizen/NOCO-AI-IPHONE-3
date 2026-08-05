import SwiftUI

struct SyncBadge: View {
    let active: Bool
    @State private var spin = false

    var body: some View {
        HStack(spacing: 6) {
            if active {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(NOCOAITheme.glowPrimary)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .onAppear {
                        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                            spin = true
                        }
                    }
            } else {
                IntelligencePulseDot(color: Color.secondary.opacity(0.5), size: 6)
            }
            Text(active ? "Sync" : "Cloud")
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.08))
                .overlay(
                    Capsule().stroke(
                        active ? NOCOAITheme.glowPrimary.opacity(0.55) : Color.clear,
                        lineWidth: 1
                    )
                )
                .shadow(color: active ? NOCOAITheme.glowPrimary.opacity(0.35) : .clear, radius: active ? 8 : 0)
        )
        .animation(.easeInOut(duration: 0.25), value: active)
    }
}
