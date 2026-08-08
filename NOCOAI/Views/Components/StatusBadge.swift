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

/// Animated rainbow-glow pen — starts a new chat from the chat toolbar.
struct RainbowNewChatButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            TimelineView(.animation(minimumInterval: 0.08, paused: false)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let spin = (t.truncatingRemainder(dividingBy: 3.2) / 3.2) * 360
                let pulse = 0.92 + 0.08 * abs(sin(t * 2.6))
                let colors: [Color] = [
                    Color(red: 1.0, green: 0.35, blue: 0.55),
                    Color(red: 1.0, green: 0.72, blue: 0.25),
                    Color(red: 0.35, green: 0.95, blue: 0.55),
                    Color(red: 0.25, green: 0.75, blue: 1.0),
                    Color(red: 0.65, green: 0.45, blue: 1.0),
                    Color(red: 1.0, green: 0.35, blue: 0.55)
                ]
                ZStack {
                    Circle()
                        .fill(
                            AngularGradient(colors: colors, center: .center, angle: .degrees(spin))
                        )
                        .frame(width: 28, height: 28)
                        .blur(radius: 4.5)
                        .opacity(0.9)
                        .scaleEffect(pulse)

                    Circle()
                        .stroke(
                            AngularGradient(colors: colors, center: .center, angle: .degrees(-spin * 0.8)),
                            lineWidth: 1.4
                        )
                        .frame(width: 26, height: 26)
                        .opacity(0.95)

                    Image(systemName: "pencil.line")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(
                            AngularGradient(colors: colors, center: .center, angle: .degrees(spin * 1.2))
                        )
                        .shadow(color: colors[Int(t * 3) % colors.count].opacity(0.7), radius: 4)
                }
                .frame(width: 30, height: 30)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Neuer Chat")
    }
}
