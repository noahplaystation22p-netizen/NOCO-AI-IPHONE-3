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
    var cornerRadius: CGFloat = 30

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
    func intelligenceShimmerBorder(cornerRadius: CGFloat = 30) -> some View {
        modifier(IntelligenceShimmerBorder(cornerRadius: cornerRadius))
    }
}

// MARK: - Extra Apple Intelligence motion kit

struct IntelligencePulseDot: View {
    var color: Color = NOCOAITheme.success
    var size: CGFloat = 9
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.35))
                .frame(width: size * 2.4, height: size * 2.4)
                .scaleEffect(pulse ? 1.35 : 0.7)
                .opacity(pulse ? 0 : 0.7)
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.8), radius: 6)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

struct IntelligenceProgressRing: View {
    var progress: Double // 0...1
    var label: String
    var valueText: String
    var tint: Color = NOCOAITheme.glowPrimary

    @State private var appear = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: appear ? min(max(progress, 0), 1) : 0)
                    .stroke(
                        AngularGradient(
                            colors: [tint, NOCOAITheme.glowSecondary, NOCOAITheme.glowAccent, tint],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tint.opacity(0.45), radius: 8)
                Text(valueText)
                    .font(.caption.weight(.bold))
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 72, height: 72)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.78)) {
                appear = true
            }
        }
        .onChange(of: progress) { _, _ in
            appear = false
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) {
                appear = true
            }
        }
    }
}

/// Large studio tile chrome (wrap with Button / NavigationLink).
struct IntelligenceFeatureTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var accent: Color = NOCOAITheme.glowPrimary

    @State private var breathe = false
    @State private var spin = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [
                                    accent.opacity(breathe ? 0.28 : 0.14),
                                    .clear
                                ],
                                center: .topTrailing,
                                startRadius: 4,
                                endRadius: 120
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            AngularGradient(
                                colors: [
                                    accent.opacity(0.7),
                                    NOCOAITheme.glowSecondary.opacity(0.35),
                                    NOCOAITheme.glowAccent.opacity(0.45),
                                    accent.opacity(0.15),
                                    accent.opacity(0.7)
                                ],
                                center: .center,
                                angle: .degrees(spin ? 360 : 0)
                            ),
                            lineWidth: 1.3
                        )
                )
                .shadow(color: accent.opacity(0.25), radius: 16, y: 6)

            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.18))
                        .frame(width: 44, height: 44)
                        .blur(radius: 2)
                    Image(systemName: systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(accent)
                        .symbolEffect(.pulse, options: .repeating.speed(0.4))
                }
                Spacer(minLength: 8)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, minHeight: 148)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = true }
            withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}

struct IntelligenceHeroBanner: View {
    var title: String
    var subtitle: String
    var online: Bool

    @State private var shimmer = false

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    NOCOAITheme.glowPrimary.opacity(0.55),
                                    NOCOAITheme.glowSecondary.opacity(0.25),
                                    NOCOAITheme.glowAccent.opacity(0.4)
                                ],
                                startPoint: shimmer ? .topLeading : .bottomTrailing,
                                endPoint: shimmer ? .bottomTrailing : .topLeading
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: NOCOAITheme.glowPrimary.opacity(0.2), radius: 20, y: 8)

            HStack(spacing: 14) {
                ZStack {
                    IntelligenceOrbitRings(size: 64)
                        .opacity(0.55)
                    Image(systemName: "sparkles")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(NOCOAITheme.accent)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.bold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        IntelligencePulseDot(color: online ? NOCOAITheme.success : NOCOAITheme.danger, size: 7)
                        Text(online ? "Intelligence Sync aktiv" : "Offline")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(online ? NOCOAITheme.success : NOCOAITheme.danger)
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
    }
}

struct IntelligenceGeneratingOverlay: View {
    var progress: Double
    var status: String

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                IntelligenceOrbitRings(size: 90)
                Circle()
                    .trim(from: 0, to: max(0.05, min(progress, 1)))
                    .stroke(
                        AngularGradient(
                            colors: [NOCOAITheme.glowPrimary, NOCOAITheme.glowSecondary, NOCOAITheme.glowAccent],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 54, height: 54)
                    .rotationEffect(.degrees(-90))
                Image(systemName: "paintbrush.pointed.fill")
                    .foregroundStyle(NOCOAITheme.accent)
                    .symbolEffect(.pulse, options: .repeating)
            }
            Text(status)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            IntelligenceShimmerLine()
                .frame(width: 140)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .intelligenceShimmerBorder(cornerRadius: 22)
        )
    }
}

struct IntelligenceTabGlow: ViewModifier {
    var active: Bool

    func body(content: Content) -> some View {
        content
            .shadow(color: active ? NOCOAITheme.glowPrimary.opacity(0.55) : .clear, radius: active ? 10 : 0)
            .scaleEffect(active ? 1.02 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: active)
    }
}

extension View {
    func intelligenceTabGlow(_ active: Bool) -> some View {
        modifier(IntelligenceTabGlow(active: active))
    }
}

// MARK: - v3.3 motion

/// Soft breathing aurora behind content — Apple Intelligence feel.
struct IntelligenceBreathingAura: View {
    @State private var breath = false

    var body: some View {
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            NOCOAITheme.glowPrimary.opacity(breath ? 0.28 : 0.12),
                            .clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 180
                    )
                )
                .frame(width: 340, height: 220)
                .scaleEffect(breath ? 1.12 : 0.92)
                .offset(y: -80)

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            NOCOAITheme.glowAccent.opacity(breath ? 0.18 : 0.08),
                            .clear
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 140
                    )
                )
                .frame(width: 260, height: 180)
                .scaleEffect(breath ? 1.08 : 0.95)
                .offset(x: 40, y: 120)
        }
        .blur(radius: 28)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                breath = true
            }
        }
    }
}

/// Horizontal waveform ribbon (chat / studio headers).
struct IntelligenceWaveRibbon: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<18, id: \.self) { i in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                NOCOAITheme.glowPrimary,
                                NOCOAITheme.glowSecondary,
                                NOCOAITheme.glowAccent
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 3, height: barHeight(for: i))
                    .opacity(0.55 + Double(i % 4) * 0.1)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                phase = true
            }
        }
        .allowsHitTesting(false)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let base: CGFloat = 6 + CGFloat((index * 3) % 7) * 2.2
        let boost: CGFloat = phase ? (index % 2 == 0 ? 8 : -4) : (index % 2 == 0 ? -4 : 8)
        return max(4, base + boost)
    }
}

/// Morphing glow that reacts to online / sync state.
struct IntelligenceConnectionGlow: View {
    var online: Bool
    var syncing: Bool
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(
                (online ? NOCOAITheme.success : NOCOAITheme.danger)
                    .opacity(pulse ? 0.35 : 0.12)
            )
            .frame(width: syncing ? 56 : 40, height: syncing ? 56 : 40)
            .blur(radius: 14)
            .scaleEffect(pulse ? 1.25 : 0.85)
            .animation(.easeInOut(duration: syncing ? 0.7 : 1.6).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
            .onChange(of: online) { _, _ in
                pulse = false
                withAnimation { pulse = true }
            }
    }
}

struct IntelligenceMessageArrive: ViewModifier {
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .scaleEffect(shown ? 1 : 0.96)
            .onAppear {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                    shown = true
                }
            }
    }
}

extension View {
    func intelligenceMessageArrive() -> some View {
        modifier(IntelligenceMessageArrive())
    }
}
