import SwiftUI

struct SyncBadge: View {
    let active: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(active ? NOCOAITheme.success : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
            Text(active ? "Sync aktiv" : "Sync")
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }
}
