import SwiftUI

struct StatusBadge: View {
    let online: Bool
    let label: String
    /// Optional freshness hint, e.g. "gerade eben" / "vor 12s"
    var detail: String? = nil

    var body: some View {
        TimelineView(.animation(minimumInterval: online ? 0.12 : 1.0, paused: !online)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let spin = (t.truncatingRemainder(dividingBy: 5.5) / 5.5) * 360
            let rainbow: [Color] = [
                Color(red: 0.95, green: 0.42, blue: 0.72),
                Color(red: 1.0, green: 0.72, blue: 0.32),
                Color(red: 0.35, green: 0.92, blue: 0.62),
                Color(red: 0.32, green: 0.72, blue: 1.0),
                Color(red: 0.58, green: 0.45, blue: 1.0),
                Color(red: 0.95, green: 0.42, blue: 0.72)
            ]
            HStack(spacing: 8) {
                if online {
                    Circle()
                        .fill(
                            AngularGradient(colors: rainbow, center: .center, angle: .degrees(spin))
                        )
                        .frame(width: 8, height: 8)
                        .shadow(color: rainbow[2].opacity(0.55), radius: 3)
                } else {
                    Circle()
                        .fill(NOCOAITheme.danger)
                        .frame(width: 8, height: 8)
                        .opacity(0.9)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            online
                            ? AnyShapeStyle(
                                AngularGradient(colors: rainbow, center: .center, angle: .degrees(spin * 0.7))
                            )
                            : AnyShapeStyle(Color.primary.opacity(0.75))
                        )
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
                    .fill(Color.primary.opacity(online ? 0.06 : 0.08))
                    .overlay(
                        Capsule()
                            .stroke(
                                online
                                ? AngularGradient(colors: rainbow.map { $0.opacity(0.55) }, center: .center, angle: .degrees(-spin))
                                : AngularGradient(colors: [NOCOAITheme.danger.opacity(0.45), NOCOAITheme.danger.opacity(0.25)], center: .center),
                                lineWidth: online ? 1.15 : 1
                            )
                    )
                    .shadow(color: online ? rainbow[3].opacity(0.22) : .clear, radius: online ? 6 : 0)
            )
        }
        .animation(.easeInOut(duration: 0.45), value: online)
        .animation(.easeInOut(duration: 0.45), value: label)
        .animation(.easeInOut(duration: 0.35), value: detail)
    }
}

/// Subtle iridescent chat title (e.g. "NOCO Speak") — Apple Intelligence–like, not flashy.
struct RainbowChatTitle: View {
    let title: String

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.14, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let spin = (t.truncatingRemainder(dividingBy: 7.5) / 7.5) * 360
            let colors: [Color] = [
                Color(red: 0.45, green: 0.62, blue: 1.0),
                Color(red: 0.55, green: 0.88, blue: 0.95),
                Color(red: 0.72, green: 0.55, blue: 1.0),
                Color(red: 0.95, green: 0.55, blue: 0.78),
                Color(red: 0.45, green: 0.62, blue: 1.0)
            ]
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: colors,
                        startPoint: UnitPoint(x: 0.15 + 0.1 * sin(t * 0.7), y: 0),
                        endPoint: UnitPoint(x: 0.85 + 0.1 * cos(t * 0.55), y: 1)
                    )
                )
                .shadow(color: colors[Int(spin / 90) % colors.count].opacity(0.28), radius: 5)
                .lineLimit(1)
        }
        .accessibilityAddTraits(.isHeader)
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
