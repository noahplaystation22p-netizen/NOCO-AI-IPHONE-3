import SwiftUI

/// Animated intelligence wave — color encodes Live Screen phase.
struct LiveScreenIntelligenceWave: View {
    var phase: LiveScreenPhase

    private var amplitude: CGFloat {
        switch phase {
        case .idle: return 4
        case .done: return 6
        default: return 11
        }
    }

    private var speed: Double {
        phase == .understanding ? 2.4 : 1.6
    }

    private var lineWidth: CGFloat {
        phase == .idle ? 2 : 3
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            waveCanvas(time: timeline.date.timeIntervalSinceReferenceDate)
        }
        .frame(height: 36)
        .blur(radius: phase == .idle ? 0.2 : 0.4)
        .animation(.easeInOut(duration: 0.45), value: phase)
    }

    private func waveCanvas(time: TimeInterval) -> some View {
        Canvas { context, size in
            let midY = size.height * 0.5
            let amp = amplitude
            let spd = speed
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                let y = midY
                    + sin((x / size.width) * .pi * 3 + time * spd) * amp
                    + sin((x / size.width) * .pi * 7 + time * spd * 1.3) * (amp * 0.35)
                if x == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                x += 3
            }
            let gradient = Gradient(colors: [
                phase.color.opacity(0.2),
                phase.color,
                Color(red: 1, green: 0.7, blue: 0.85).opacity(0.85),
                phase.color.opacity(0.35)
            ])
            context.stroke(
                path,
                with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
        }
    }
}

/// Premium Live Screen status — glass + rainbow + phase emoji.
struct LiveScreenStatusTheater: View {
    var phase: LiveScreenPhase
    var status: String
    @State private var spin = false
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 10) {
            statusOrb
            Text("\(phase.emoji) \(phase.title)")
                .font(.subheadline.weight(.bold))
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            LiveScreenIntelligenceWave(phase: phase)
                .padding(.horizontal, 8)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background { statusBackground }
        .onAppear {
            withAnimation(.linear(duration: 5.5).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) { pulse = true }
        }
        .animation(.easeInOut(duration: 0.4), value: phase)
    }

    private var statusOrb: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            phase.color,
                            Color(red: 0.45, green: 0.85, blue: 1.0),
                            Color(red: 0.85, green: 0.45, blue: 0.95),
                            Color(red: 1.0, green: 0.75, blue: 0.45),
                            phase.color
                        ],
                        center: .center
                    )
                )
                .frame(width: 64, height: 64)
                .blur(radius: 10)
                .opacity(pulse ? 0.9 : 0.55)
                .rotationEffect(.degrees(spin ? 360 : 0))

            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 48, height: 48)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.55), phase.color.opacity(0.4), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )

            Text(phase.emoji)
                .font(.system(size: 22))
                .scaleEffect(pulse ? 1.06 : 0.94)
        }
    }

    private var statusBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                phase.color.opacity(0.55),
                                Color.white.opacity(0.25),
                                phase.color.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}

/// Living agent core — rainbow/glass identity orb with phase colors.
struct AgentCoreOrb: View {
    var isActive: Bool
    var progress: Double
    var phaseColor: Color = Color(red: 0.45, green: 0.72, blue: 1.0)
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            phaseColor,
                            Color(red: 0.45, green: 0.55, blue: 1.0),
                            Color(red: 0.85, green: 0.45, blue: 0.95),
                            Color(red: 1.0, green: 0.7, blue: 0.45),
                            phaseColor
                        ],
                        center: .center
                    )
                )
                .frame(width: 72, height: 72)
                .blur(radius: isActive ? 12 : 6)
                .opacity(0.9)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: isActive ? 4.5 : 14).repeatForever(autoreverses: false), value: spin)
                .animation(.easeInOut(duration: 0.45), value: phaseColor)

            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 54, height: 54)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.55), .clear, phaseColor.opacity(0.45)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )

            Image(systemName: "cpu.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(phaseColor)
                .symbolEffect(.pulse, options: .repeating, isActive: isActive)

            Circle()
                .trim(from: 0, to: max(0.04, progress / 100))
                .stroke(phaseColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 64, height: 64)
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: progress)
        }
        .onAppear { spin = true }
    }
}
