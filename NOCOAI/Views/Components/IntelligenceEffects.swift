import SwiftUI

/// Soft Apple-Intelligence atmosphere: drifting glow orbs + shimmer.
struct IntelligenceAtmosphere: View {
    @Environment(\.colorScheme) private var scheme
    @State private var phase = false

    var body: some View {
        ZStack {
            NOCOAITheme.intelligenceBackground(for: scheme)

            Circle()
                .fill(NOCOAITheme.glowPrimary.opacity(scheme == .dark ? 0.38 : 0.24))
                .frame(width: 300, height: 300)
                .blur(radius: 75)
                .offset(x: phase ? 46 : -54, y: phase ? -90 : -36)

            Circle()
                .fill(NOCOAITheme.glowSecondary.opacity(scheme == .dark ? 0.3 : 0.18))
                .frame(width: 260, height: 260)
                .blur(radius: 65)
                .offset(x: phase ? -70 : 78, y: phase ? 130 : 50)

            Circle()
                .fill(NOCOAITheme.glowAccent.opacity(scheme == .dark ? 0.22 : 0.12))
                .frame(width: 220, height: 220)
                .blur(radius: 58)
                .offset(x: phase ? 34 : -24, y: phase ? 48 : 110)

            // Soft conic shimmer veil
            AngularGradient(
                colors: [
                    NOCOAITheme.glowPrimary.opacity(0.08),
                    .clear,
                    NOCOAITheme.glowSecondary.opacity(0.07),
                    .clear,
                    NOCOAITheme.glowAccent.opacity(0.06),
                    .clear
                ],
                center: .center
            )
            .blur(radius: 40)
            .opacity(phase ? 0.9 : 0.45)
            .scaleEffect(1.4)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 7.5).repeatForever(autoreverses: true)) {
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
                        .offset(y: animate ? -16 : 12)
                        .opacity(animate ? 0.95 : 0.3)
                        .animation(
                            .easeInOut(duration: 1.9 + Double(i % 5) * 0.28)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.11),
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

/// Orbiting rings — Apple Intelligence pairing vibe.
struct IntelligenceOrbitRings: View {
    @State private var spin = false
    var size: CGFloat = 220

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                NOCOAITheme.glowPrimary.opacity(0.55 - Double(i) * 0.12),
                                .clear,
                                NOCOAITheme.glowSecondary.opacity(0.4),
                                .clear,
                                NOCOAITheme.glowAccent.opacity(0.35),
                                .clear
                            ],
                            center: .center
                        ),
                        lineWidth: 1.2
                    )
                    .frame(width: size - CGFloat(i) * 28, height: size - CGFloat(i) * 28)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(
                        .linear(duration: 10 + Double(i) * 3).repeatForever(autoreverses: false),
                        value: spin
                    )
                    .opacity(0.7 - Double(i) * 0.15)
            }
        }
        .onAppear { spin = true }
        .allowsHitTesting(false)
    }
}

struct PairingPulseSteps: View {
    @State private var step = 0

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(i == step ? NOCOAITheme.accent : Color.primary.opacity(0.12))
                    .frame(width: i == step ? 22 : 9, height: 9)
                    .shadow(color: i == step ? NOCOAITheme.glowPrimary : .clear, radius: 8)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: step)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 800_000_000)
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
                    : AnyShapeStyle(.ultraThinMaterial)
            )
            .overlay {
                if isUser {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                } else {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    NOCOAITheme.glowPrimary.opacity(scheme == .dark ? 0.35 : 0.2),
                                    NOCOAITheme.glowSecondary.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            }
            .shadow(
                color: isUser ? NOCOAITheme.glowPrimary.opacity(0.4) : NOCOAITheme.glowSecondary.opacity(0.18),
                radius: isUser ? 16 : 12,
                y: 4
            )
    }
}

struct StreamingGlowCursor: View {
    @State private var on = false

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [NOCOAITheme.glowPrimary, NOCOAITheme.glowSecondary],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 7, height: 18)
            .shadow(color: NOCOAITheme.glowPrimary, radius: 8)
            .opacity(on ? 1 : 0.2)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

/// Soft thinking indicator (Windows-style, Apple soft)
struct IntelligenceThinkingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(NOCOAITheme.glowPrimary)
                    .frame(width: 7, height: 7)
                    .scaleEffect(phase == i ? 1.35 : 0.85)
                    .opacity(phase == i ? 1 : 0.35)
                    .shadow(color: NOCOAITheme.glowPrimary.opacity(phase == i ? 0.8 : 0), radius: 6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(GlowBubbleBackground(isUser: false))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 320_000_000)
                phase = (phase + 1) % 3
            }
        }
    }
}

struct IntelligenceShimmerBorder: ViewModifier {
    @State private var spin = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(
                        AngularGradient(
                            colors: [
                                NOCOAITheme.glowPrimary.opacity(0.8),
                                NOCOAITheme.glowSecondary.opacity(0.35),
                                NOCOAITheme.glowAccent.opacity(0.55),
                                NOCOAITheme.glowPrimary.opacity(0.2),
                                NOCOAITheme.glowPrimary.opacity(0.8)
                            ],
                            center: .center,
                            angle: .degrees(spin ? 360 : 0)
                        ),
                        lineWidth: 1.4
                    )
                    .animation(.linear(duration: 5).repeatForever(autoreverses: false), value: spin)
            )
            .onAppear { spin = true }
    }
}

extension View {
    func intelligenceShimmerBorder() -> some View {
        modifier(IntelligenceShimmerBorder())
    }
}
