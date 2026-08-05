import SwiftUI

struct SyncBadge: View {
    let active: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(active ? NOCOAITheme.success : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
                .shadow(color: active ? NOCOAITheme.success.opacity(0.8) : .clear, radius: active ? 6 : 0)
            Text(active ? "Sync aktiv" : "Cloud")
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.08))
                .overlay(
                    Capsule().stroke(active ? NOCOAITheme.glowPrimary.opacity(0.45) : Color.clear, lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.25), value: active)
    }
}
