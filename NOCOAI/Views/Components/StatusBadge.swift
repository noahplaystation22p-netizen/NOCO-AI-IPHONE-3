import SwiftUI

struct StatusBadge: View {
    let online: Bool
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(online ? NOCOAITheme.success : NOCOAITheme.danger)
                .frame(width: 10, height: 10)
                .shadow(color: (online ? NOCOAITheme.success : NOCOAITheme.danger).opacity(0.6), radius: 6)
            Text(label)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }
}
