import SwiftUI

struct SyncBadge: View {
    let active: Bool
    @State private var spin = false

    var body: some View {
        Group {
            if active {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(NOCOAITheme.glowPrimary)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .onAppear {
                            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                                spin = true
                            }
                        }
                    Text("Sync")
                        .font(.caption2.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .overlay(
                            Capsule().stroke(NOCOAITheme.glowPrimary.opacity(0.55), lineWidth: 1)
                        )
                        .shadow(color: NOCOAITheme.glowPrimary.opacity(0.35), radius: 8)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: active)
    }
}
