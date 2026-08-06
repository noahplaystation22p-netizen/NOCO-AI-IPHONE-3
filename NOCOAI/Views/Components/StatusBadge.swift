import SwiftUI

struct StatusBadge: View {
    let online: Bool
    let label: String
    /// Optional freshness hint, e.g. "gerade eben" / "vor 12s"
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            IntelligencePulseDot(
                color: online ? NOCOAITheme.success : NOCOAITheme.danger,
                size: 8
            )
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.interpolate)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, detail == nil ? 8 : 6)
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
        .animation(.easeInOut(duration: 0.35), value: detail)
    }
}
