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
                .fill(NOCOAITheme.glowAccent.opacity(scheme == .dark ? 0.18 : 0.10))
                .frame(width: 240, height: 240)
                .blur(radius: 70)
                .offset(x: phase ? 20 : -40, y: phase ? 90 : 20)

            AngularGradient(
                colors: [
                    NOCOAITheme.glowPrimary.opacity(0.1),
                    .clear,
                    NOCOAITheme.glowSecondary.opacity(0.08),
                    .clear,
                    NOCOAITheme.glowAccent.opacity(0.09),
                    .clear
                ],
                center: .center
            )
            .blur(radius: 48)
            .opacity(phase ? 0.95 : 0.4)
            .scaleEffect(1.45)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 9.5).repeatForever(autoreverses: true)) {
                phase = true
            }
        }
    }
}

struct FloatingIntelligenceDots: View {
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                        .offset(y: (!reduceMotion && animate) ? -16 : 0)
                        .opacity((!reduceMotion && animate) ? 0.95 : 0.45)
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeInOut(duration: 1.9 + Double(i % 5) * 0.28)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.11),
                            value: animate
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            animate = true
        }
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
    var streaming: Bool = false
    @Environment(\.colorScheme) private var scheme
    @State private var shimmer = false

    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                isUser
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [
                                NOCOAITheme.accent,
                                NOCOAITheme.accentSecondary,
                                NOCOAITheme.glowAccent.opacity(0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    : AnyShapeStyle(.ultraThinMaterial)
            )
            .overlay {
                if isUser {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.32), lineWidth: 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.22), .clear],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                                .allowsHitTesting(false)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            AngularGradient(
                                colors: streaming
                                ? [
                                    NOCOAITheme.glowPrimary.opacity(shimmer ? 0.85 : 0.35),
                                    NOCOAITheme.glowSecondary.opacity(0.55),
                                    NOCOAITheme.glowAccent.opacity(0.45),
                                    NOCOAITheme.glowPrimary.opacity(shimmer ? 0.35 : 0.85)
                                ]
                                : [
                                    NOCOAITheme.glowPrimary.opacity(scheme == .dark ? 0.38 : 0.22),
                                    NOCOAITheme.glowAccent.opacity(0.18),
                                    NOCOAITheme.glowSecondary.opacity(0.14)
                                ],
                                center: .center
                            ),
                            lineWidth: streaming ? 1.4 : 1
                        )
                }
            }
            .overlay {
                if streaming && !isUser {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    NOCOAITheme.glowPrimary.opacity(shimmer ? 0.12 : 0.04),
                                    .clear,
                                    NOCOAITheme.glowSecondary.opacity(shimmer ? 0.1 : 0.03)
                                ],
                                startPoint: shimmer ? .topLeading : .bottomTrailing,
                                endPoint: shimmer ? .bottomTrailing : .topLeading
                            )
                        )
                        .allowsHitTesting(false)
                }
            }
            .shadow(
                color: isUser
                    ? NOCOAITheme.glowPrimary.opacity(0.42)
                    : (streaming ? NOCOAITheme.glowPrimary.opacity(0.35) : NOCOAITheme.glowSecondary.opacity(0.16)),
                radius: streaming ? 20 : (isUser ? 18 : 14),
                y: 5
            )
            .onAppear {
                guard streaming else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    shimmer = true
                }
            }
            .onChange(of: streaming) { _, on in
                if on {
                    withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                        shimmer = true
                    }
                } else {
                    shimmer = false
                }
            }
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

// MARK: - Extra NOCO motion kit

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
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [
                                    accent.opacity(breathe ? 0.26 : 0.12),
                                    NOCOAITheme.glowAccent.opacity(0.06),
                                    .clear
                                ],
                                center: .topTrailing,
                                startRadius: 4,
                                endRadius: 130
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.1), .clear],
                                startPoint: .topLeading,
                                endPoint: .center
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(
                            AngularGradient(
                                colors: [
                                    accent.opacity(0.65),
                                    NOCOAITheme.glowSecondary.opacity(0.3),
                                    NOCOAITheme.glowAccent.opacity(0.4),
                                    accent.opacity(0.12),
                                    accent.opacity(0.65)
                                ],
                                center: .center,
                                angle: .degrees(spin ? 360 : 0)
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: accent.opacity(0.22), radius: 18, y: 7)

            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.16))
                        .frame(width: 46, height: 46)
                        .blur(radius: 2)
                    Image(systemName: systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(accent)
                        .symbolEffect(.pulse, options: .repeating.speed(0.35))
                }
                Spacer(minLength: 8)
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, minHeight: 152)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { breathe = true }
            withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) { spin = true }
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
                        Text(online ? "NOCO Sync aktiv" : "Offline")
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
    var insight: String = ""
    var etaSeconds: Int? = nil

    var body: some View {
        ImageCreationTheater(
            progress: progress,
            status: status,
            insight: insight,
            etaSeconds: etaSeconds
        )
    }
}

/// Full Apple-Intelligence theater for long SD waits (~4 min on CPU).
struct ImageCreationTheater: View {
    var progress: Double
    var status: String
    var insight: String
    var etaSeconds: Int?

    @State private var spin = false
    @State private var breathe = false
    @State private var sweep = false
    @State private var particlePhase = false
    @State private var hueShift = false

    private var pct: Int { Int((min(max(progress, 0), 1) * 100).rounded()) }

    private var etaLabel: String? {
        guard let eta = etaSeconds, eta > 0 else { return nil }
        if eta >= 60 { return "~\(min(8, Int(ceil(Double(eta) / 60)))) Min" }
        return "~\(eta)s"
    }

    private let rainbow: [Color] = [
        Color(red: 0.3, green: 0.85, blue: 1),
        Color(red: 0.45, green: 0.5, blue: 1),
        Color(red: 0.8, green: 0.4, blue: 1),
        Color(red: 0.95, green: 0.45, blue: 0.7),
        Color(red: 1.0, green: 0.7, blue: 0.35),
        Color(red: 0.4, green: 0.95, blue: 0.7),
        Color(red: 0.3, green: 0.85, blue: 1)
    ]

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                AngularGradient(colors: rainbow, center: .center)
                    .frame(width: 230, height: 230)
                    .blur(radius: 40)
                    .opacity(breathe ? 0.55 : 0.28)
                    .scaleEffect(breathe ? 1.1 : 0.92)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .hueRotation(.degrees(hueShift ? 20 : -14))
                    .blendMode(.plusLighter)

                // Soft aurora
                Circle()
                    .fill(NOCOAITheme.glowPrimary.opacity(breathe ? 0.28 : 0.12))
                    .frame(width: 210, height: 210)
                    .blur(radius: 36)
                    .scaleEffect(breathe ? 1.08 : 0.92)

                Circle()
                    .fill(NOCOAITheme.glowAccent.opacity(breathe ? 0.18 : 0.08))
                    .frame(width: 160, height: 160)
                    .blur(radius: 28)
                    .offset(x: breathe ? 12 : -10, y: breathe ? -8 : 10)

                IntelligenceOrbitRings(size: 150)
                    .opacity(0.55)

                // Progress ring
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 10)
                    .frame(width: 118, height: 118)

                Circle()
                    .trim(from: 0, to: max(0.04, min(progress, 1)))
                    .stroke(
                        AngularGradient(
                            colors: rainbow,
                            center: .center,
                            angle: .degrees(spin ? 360 : 0)
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: 118, height: 118)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: NOCOAITheme.glowPrimary.opacity(0.45), radius: 10)
                    .animation(.easeInOut(duration: 0.55), value: progress)

                VStack(spacing: 2) {
                    Text("\(pct)%")
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(NOCOAITheme.accent)
                        .contentTransition(.numericText())
                    if let etaLabel {
                        Text(etaLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                // Floating particles
                ForEach(0..<6, id: \.self) { i in
                    Circle()
                        .fill(dotColor(i))
                        .frame(width: 4, height: 4)
                        .offset(
                            x: cos(Double(i) / 6 * .pi * 2) * (particlePhase ? 72 : 56),
                            y: sin(Double(i) / 6 * .pi * 2) * (particlePhase ? 72 : 56)
                        )
                        .opacity(particlePhase ? 0.95 : 0.35)
                        .blur(radius: 0.4)
                }
            }
            .frame(height: 200)
            .drawingGroup() // Flatten layers — much smoother during SD wait

            // Sweeping shimmer bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 8)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: Array(rainbow.prefix(5)),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(18, geo.size.width * min(max(progress, 0.04), 1)), height: 8)
                        .shadow(color: NOCOAITheme.glowPrimary.opacity(0.5), radius: 6)
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: progress)

                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 36, height: 8)
                        .offset(x: sweep ? max(0, geo.size.width * min(progress, 1) - 36) : 0)
                        .opacity(0.5)
                }
            }
            .frame(height: 8)
            .padding(.horizontal, 28)

            VStack(spacing: 6) {
                Text(status)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                if !insight.isEmpty {
                    Text(insight)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .id(insight)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                Text("Dein PC rechnet — das kann ein paar Minuten dauern.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 12)
            .animation(.easeInOut(duration: 0.35), value: insight)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .intelligenceShimmerBorder(cornerRadius: 26)
                .shadow(color: NOCOAITheme.glowPrimary.opacity(0.2), radius: 20, y: 8)
        )
        .onAppear {
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { breathe = true }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { particlePhase = true }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { sweep = true }
            withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) { hueShift = true }
            HapticService.medium()
        }
    }

    private func dotColor(_ i: Int) -> Color {
        rainbow[i % (rainbow.count - 1)]
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

/// Soft breathing aurora behind content — NOCO feel.
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

    /// Soft aurora wash while the PC streams a reply.
    func intelligenceStreaming(_ active: Bool) -> some View {
        modifier(IntelligenceStreamingModifier(active: active))
    }
}

private struct IntelligenceStreamingModifier: ViewModifier {
    var active: Bool
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .leading) {
                if active {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    NOCOAITheme.glowPrimary.opacity(pulse ? 0.9 : 0.35),
                                    NOCOAITheme.glowSecondary.opacity(0.6),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 3)
                        .padding(.vertical, 10)
                        .offset(x: -6)
                        .shadow(color: NOCOAITheme.glowPrimary.opacity(0.6), radius: 6)
                }
            }
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            .onChange(of: active) { _, on in
                if on {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                } else {
                    pulse = false
                }
            }
    }
}

// MARK: - Pixel sphere (pairing aura — reacts when QR is found)

enum PixelSpherePhase: Equatable {
    case idle
    case locking
    case success
}

/// Fibonacci-sphere pixel orb — centered, denser, with lock/success phases.
struct PixelSphereView: View {
    var size: CGFloat = 220
    var intensity: Double = 1
    var phase: PixelSpherePhase = .idle
    var pixelCount: Int = 88

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, canvasSize in
                let mid = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let baseR = min(canvasSize.width, canvasSize.height) * 0.40
                let golden = Double.pi * (3 - sqrt(5))

                let converge: Double
                let spin: Double
                switch phase {
                case .idle:
                    converge = 1
                    spin = t * 0.55
                case .locking:
                    converge = 0.55 + 0.2 * sin(t * 6)
                    spin = t * 1.8
                case .success:
                    let pulse = abs(sin(t * 4.2))
                    converge = 0.25 + pulse * 0.95
                    spin = t * 2.4
                }

                for i in 0..<pixelCount {
                    let y = 1 - (Double(i) / Double(max(pixelCount - 1, 1))) * 2
                    let radiusAtY = sqrt(max(0, 1 - y * y))
                    let theta = golden * Double(i) + spin
                    let x = cos(theta) * radiusAtY
                    let z = sin(theta) * radiusAtY

                    let depth = (z * 0.5 + 0.75)
                    let r = baseR * CGFloat(converge)
                    let px = mid.x + CGFloat(x) * r * CGFloat(depth)
                    let py = mid.y + CGFloat(y) * r * CGFloat(depth)
                    let s = max(1.4, (phase == .success ? 4.6 : 3.4) * depth) * intensity
                    let hue = (Double(i) / Double(pixelCount) + t * 0.06).truncatingRemainder(dividingBy: 1)
                    let color = Color(hue: hue, saturation: 0.88, brightness: 1)
                        .opacity(0.28 + 0.62 * depth)
                    let rect = CGRect(x: px - s / 2, y: py - s / 2, width: s, height: s)
                    ctx.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.35), value: phase)
    }
}

/// Soft aurora ring + reactive pixels around the QR scan frame.
struct IntelligenceScanAura: View {
    var phase: PixelSpherePhase = .idle

    var body: some View {
        ZStack {
            PixelSphereView(size: 300, intensity: phase == .success ? 1.15 : 0.75, phase: phase, pixelCount: 96)
                .blur(radius: phase == .idle ? 0.4 : 0)
                .opacity(phase == .success ? 1 : 0.85)
            // Keep the scan window clear — no solid ball over the QR
            Circle()
                .fill(Color.black.opacity(0.001))
                .frame(width: 210, height: 210)
        }
        .allowsHitTesting(false)
    }
}
