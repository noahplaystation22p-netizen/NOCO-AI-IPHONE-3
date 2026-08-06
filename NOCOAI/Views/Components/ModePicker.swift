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
                            .fill(fill(for: m))
                            .overlay(
                                Capsule()
                                    .stroke(stroke(for: m), lineWidth: m == .agent && mode == m ? 1.4 : 1)
                            )
                            .shadow(color: mode == m ? accent(for: m).opacity(0.4) : .clear, radius: 8)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(mode == m ? accent(for: m) : .secondary)
                .accessibilityLabel("\(m.label), \(m.subtitle)")
            }
        }
        .intelligenceSelectionFeedback(mode)
    }

    private func accent(for m: AIMode) -> Color {
        m == .agent ? Color(red: 0.35, green: 0.78, blue: 0.72) : NOCOAITheme.accent
    }

    private func fill(for m: AIMode) -> Color {
        guard mode == m else { return Color.primary.opacity(0.05) }
        return accent(for: m).opacity(m == .agent ? 0.28 : 0.22)
    }

    private func stroke(for m: AIMode) -> Color {
        guard mode == m else { return .clear }
        return accent(for: m).opacity(0.65)
    }
}
