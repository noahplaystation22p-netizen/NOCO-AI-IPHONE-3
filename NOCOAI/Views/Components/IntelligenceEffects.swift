import SwiftUI

/// Soft Apple-Intelligence atmosphere: drifting glow orbs + shimmer.
struct IntelligenceAtmosphere: View {
    @Environment(\.colorScheme) private var scheme
    @State private var phase = false

    var body: some View {
        ZStack {
            NOCOAITheme.intelligenceBackground(for: scheme)

            Circle()
                .fill(NOCOAITheme.glowPrimary.opacity(scheme == .dark ? 0.35 : 0.22))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: phase ? 40 : -50, y: phase ? -80 : -40)

            Circle()
                .fill(NOCOAITheme.glowSecondary.opacity(scheme == .dark ? 0.28 : 0.18))
                .frame(width: 240, height: 240)
                .blur(radius: 60)
                .offset(x: phase ? -60 : 70, y: phase ? 120 : 60)

            Circle()
                .fill(NOCOAITheme.glowAccent.opacity(scheme == .dark ? 0.2 : 0.12))
                .frame(width: 200, height: 200)
                .blur(radius: 55)
                .offset(x: phase ? 30 : -20, y: phase ? 40 : 100)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                phase = true
            }
        }
    }
}

/// Floating intelligence dots for pairing / idle states.
struct FloatingIntelligenceDots: View {
    let count: Int
    @State private var animate = false

    init(count: Int = 12) {
        self.count = count
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<count, id: \.self) { i in
                    Circle()
                        .fill(dotColor(i))
                        .frame(width: CGFloat(4 + (i % 3)), height: CGFloat(4 + (i % 3)))
                        .shadow(color: dotColor(i).opacity(0.9), radius: 6)
                        .position(
                            x: CGFloat((i * 67) % Int(max(geo.size.width, 1))),
                            y: CGFloat((i * 97) % Int(max(geo.size.height, 1)))
                        )
                        .offset(y: animate ? -14 : 10)
                        .opacity(animate ? 0.95 : 0.35)
                        .animation(
                            .easeInOut(duration: 1.8 + Double(i % 5) * 0.25)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.12),
                            value: animate
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { animate = true }
    }

    private func dotColor(_ i: Int) -> Color {
        switch i % 3 {
        case 0: return NOCOAITheme.glowPrimary
        case 1: return NOCOAITheme.glowSecondary
        default: return NOCOAITheme.glowAccent
        }
    }
}

struct PairingPulseSteps: View {
    @State private var step = 0

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(i == step ? NOCOAITheme.accent : Color.primary.opacity(0.15))
                    .frame(width: 9, height: 9)
                    .shadow(color: i == step ? NOCOAITheme.glowPrimary : .clear, radius: 8)
                    .scaleEffect(i == step ? 1.25 : 1)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: step)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 850_000_000)
                step = (step + 1) % 3
            }
        }
    }
}

struct GlowBubbleBackground: View {
    let isUser: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                isUser
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [NOCOAITheme.accent, NOCOAITheme.accentSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    : AnyShapeStyle(NOCOAITheme.cardFill(for: scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        isUser
                            ? Color.white.opacity(0.25)
                            : NOCOAITheme.glowPrimary.opacity(scheme == .dark ? 0.25 : 0.15),
                        lineWidth: 1
                    )
            )
            .shadow(color: isUser ? NOCOAITheme.glowPrimary.opacity(0.45) : NOCOAITheme.glowSecondary.opacity(0.2), radius: isUser ? 16 : 10, y: 4)
    }
}

struct StreamingGlowCursor: View {
    @State private var on = false

    var body: some View {
        Capsule()
            .fill(NOCOAITheme.accent)
            .frame(width: 8, height: 18)
            .shadow(color: NOCOAITheme.glowPrimary, radius: 8)
            .opacity(on ? 1 : 0.25)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}
