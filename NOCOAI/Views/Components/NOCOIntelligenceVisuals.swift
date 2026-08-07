import SwiftUI

/// Animated intelligence wave — rainbow flow + phase accent.
struct LiveScreenIntelligenceWave: View {
    var phase: LiveScreenPhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shift = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: NOCORainbow.flow.map { $0.opacity(0.18) },
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 4)
                    .offset(x: shift ? 12 : -12)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                phase.color.opacity(0.25),
                                NOCORainbow.violet.opacity(0.85),
                                NOCORainbow.pink.opacity(0.75),
                                phase.color
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
            guard !reduceMotion else { return }
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
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) { pulse = true }
        }
        .animation(.easeInOut(duration: 0.4), value: phase)
    }

    private var statusOrb: some View {
        NOCOIntelligenceCore(
            energy: phase == .idle ? .idle : .vision,
            size: .medium,
            systemImage: nil
        )
        .overlay {
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

/// Living agent core — shared Dynamic Intelligence KI orb.
struct AgentCoreOrb: View {
    var isActive: Bool
    var progress: Double
    var phaseColor: Color = Color(red: 0.45, green: 0.72, blue: 1.0)

    private var energy: NOCOIntelligenceEnergy {
        if progress >= 99.5 { return .success }
        if isActive { return .working }
        return .idle
    }

    var body: some View {
        NOCOIntelligenceCore(
            energy: energy,
            size: .medium,
            progress: (isActive || progress > 1) ? max(0.04, min(progress / 100, 1)) : nil,
            systemImage: "cpu.fill"
        )
        .overlay {
            // Keep phase tint as a soft identity wash without fighting the rainbow core.
            Circle()
                .fill(phaseColor.opacity(isActive ? 0.12 : 0.05))
                .frame(width: 54, height: 54)
                .blur(radius: 8)
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.4), value: phaseColor)
        .animation(.easeInOut(duration: 0.35), value: isActive)
    }
}
