import SwiftUI

struct StatusBadge: View {
    let online: Bool
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            IntelligencePulseDot(
                color: online ? NOCOAITheme.success : NOCOAITheme.danger,
                size: 8
            )
            Text(label)
                .font(.subheadline.weight(.semibold))
                .contentTransition(.interpolate)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.08))
                .overlay(
                    Capsule()
                        .stroke(
                            (online ? NOCOAITheme.success : NOCOAITheme.danger).opacity(0.35),
                            lineWidth: 1
                        )
                )
        )
        .animation(.easeInOut(duration: 0.45), value: online)
        .animation(.easeInOut(duration: 0.45), value: label)
    }
}
