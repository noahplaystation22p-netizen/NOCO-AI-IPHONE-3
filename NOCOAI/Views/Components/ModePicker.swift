import SwiftUI

struct ModePicker: View {
    @Binding var mode: AIMode

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AIMode.allCases) { m in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        mode = m
                    }
                    HapticService.modeChange()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: m.systemImage)
                            .font(.caption2.weight(.bold))
                        Text(m.label)
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background {
                        Capsule()
                            .fill(mode == m ? NOCOAITheme.accent.opacity(0.22) : Color.primary.opacity(0.05))
                            .overlay(
                                Capsule()
                                    .stroke(
                                        mode == m
                                            ? NOCOAITheme.glowPrimary.opacity(0.55)
                                            : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: mode == m ? NOCOAITheme.glowPrimary.opacity(0.35) : .clear, radius: 8)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(mode == m ? NOCOAITheme.accent : .secondary)
                .accessibilityLabel("\(m.label), \(m.subtitle)")
            }
        }
        .intelligenceSelectionFeedback(mode)
    }
}
