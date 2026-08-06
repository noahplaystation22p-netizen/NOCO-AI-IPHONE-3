import SwiftUI

/// Animated intelligence wave — color encodes Live Screen phase.
struct LiveScreenIntelligenceWave: View {
    var phase: LiveScreenPhase
    @State private var shift = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Capsule()
                    .fill(phase.color.opacity(0.25))
                    .frame(height: 4)
                    .offset(x: shift ? 12 : -12)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                phase.color.opacity(0.2),
                                phase.color,
                                Color(red: 1, green: 0.7, blue: 0.85).opacity(0.8)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * 0.55, height: phase == .idle ? 3 : 5)
                    .offset(x: shift ? geo.size.width * 0.2 : -geo.size.width * 0.2)
                    .blur(radius: 0.4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 36)
        .onAppear {
            withAnimation(.easeInOut(duration: phase == .understanding ? 0.9 : 1.4).repeatForever(autoreverses: true)) {
                shift = true
            }
        }
        .animation(.easeInOut(duration: 0.35), value: phase)
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
