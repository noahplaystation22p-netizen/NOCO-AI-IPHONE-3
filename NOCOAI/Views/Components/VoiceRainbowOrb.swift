import SwiftUI

/// Apple-Intelligence voice stage: soft aurora + thin rings + reactive waveform — not a fat orb.
struct IntelligenceVoiceStage: View {
    var phase: VoicePhase
    var level: CGFloat
    var bands: [CGFloat] = Array(repeating: 0.15, count: 16)

    @State private var spin = false
    @State private var breathe = false

    private var active: Bool {
        switch phase {
        case .listening, .processing, .speaking: return true
        default: return false
        }
    }

    private var intensity: Double {
        switch phase {
        case .listening: return 0.45 + Double(level) * 0.55
        case .processing: return 0.8
        case .speaking: return 0.85 + Double(level) * 0.15
        case .error: return 0.35
        case .idle: return 0.35
        }
    }

    var body: some View {
        let interval: Double = {
            switch phase {
            case .listening: return 1.0 / 20.0
            case .speaking: return 1.0 / 24.0
            case .processing: return 1.0 / 12.0
            default: return 1.0 / 8.0
            }
        }()
        TimelineView(.animation(minimumInterval: interval)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                auroraField
                softRings
                centerWaveform(t: t)
                statusSpark
            }
            .scaleEffect(active ? 1 + level * 0.05 : 1)
            .animation(.easeOut(duration: 0.08), value: level)
        }
        .frame(height: 250)
        .onAppear {
            guard active else { return }
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }
        }
        .onChange(of: active) { _, isActive in
            if isActive {
                withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) { spin = true }
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }
            } else {
                spin = false
                breathe = false
            }
        }
    }

    private var auroraField: some View {
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.45, green: 0.78, blue: 1).opacity(0.38 * intensity),
                            Color(red: 0.5, green: 0.9, blue: 0.85).opacity(0.16 * intensity),
                            .clear
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 170
                    )
                )
                .frame(width: 350, height: 230)
                .blur(radius: 30)
                .scaleEffect(breathe ? 1.07 : 0.93)

            Ellipse()
                .fill(Color(red: 0.35, green: 0.92, blue: 0.75).opacity(0.16 * intensity))
                .frame(width: 270, height: 150)
                .blur(radius: 36)
                .offset(x: breathe ? 22 : -20, y: breathe ? -12 : 16)

            Ellipse()
                .fill(Color(red: 0.55, green: 0.7, blue: 1).opacity(0.1 * intensity))
                .frame(width: 200, height: 120)
                .blur(radius: 28)
                .offset(x: breathe ? -20 : 18, y: 18)
        }
    }

    private var softRings: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(red: 0.4, green: 0.8, blue: 1).opacity(0.55),
                                .clear,
                                Color(red: 0.7, green: 0.45, blue: 1).opacity(0.4),
                                .clear,
                                Color(red: 0.4, green: 0.95, blue: 0.75).opacity(0.35),
                                .clear
                            ],
                            center: .center
                        ),
                        lineWidth: 1.1
                    )
                    .frame(width: 168 + CGFloat(i) * 36, height: 168 + CGFloat(i) * 36)
                    .rotationEffect(.degrees((i % 2 == 0 ? 1 : -1) * (spin ? 360 : 0)))
                    .opacity(0.35 + intensity * 0.35)
                    .scaleEffect(1 + level * (phase == .listening ? 0.18 : 0.06))
                    .animation(.easeOut(duration: 0.05), value: level)
            }
        }
    }

    private func centerWaveform(t: Double) -> some View {
        let count = max(bands.count, 12)
        return HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: barColors(i),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 5, height: barHeight(i, t: t))
                    .shadow(color: barColors(i)[0].opacity(0.45 + Double(level) * 0.4), radius: active ? 6 : 0)
            }
        }
        .frame(height: 88)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    Color(red: 0.4, green: 0.8, blue: 1).opacity(0.55 + Double(level) * 0.35),
                                    Color(red: 0.7, green: 0.4, blue: 1).opacity(0.35),
                                    Color(red: 0.4, green: 0.95, blue: 0.7).opacity(0.4),
                                    Color(red: 0.4, green: 0.8, blue: 1).opacity(0.55)
                                ],
                                center: .center
                            ),
                            lineWidth: 1.2 + level * 1.2
                        )
                        .rotationEffect(.degrees(spin ? 360 : 0))
                )
                .shadow(color: Color(red: 0.45, green: 0.7, blue: 1).opacity(0.22 + Double(level) * 0.35), radius: 14 + level * 18)
        )
        .scaleEffect(1 + level * (phase == .listening ? 0.12 : 0.05))
        .animation(.easeOut(duration: 0.05), value: level)
        .animation(.easeOut(duration: 0.05), value: bands)
    }

    private var statusSpark: some View {
        Image(systemName: glyph)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 118)
            .symbolEffect(.pulse, options: .repeating, isActive: phase == .processing || phase == .listening)
            .opacity(0.85)
    }

    private func barHeight(_ i: Int, t: Double) -> CGFloat {
        let band: CGFloat
        if i < bands.count {
            band = bands[i]
        } else if !bands.isEmpty {
            band = bands[i % bands.count]
        } else {
            band = level
        }

        let mid = abs(Double(i) - Double(max(bands.count, 1) - 1) / 2.0)
        let envelope = max(0.2, 1.0 - mid / 10.0)

        switch phase {
        case .listening:
            // True visualizer: loud = high bars, quiet = low
            return max(6, 10 + band * 92 * CGFloat(envelope) + level * 18)
        case .speaking:
            let wave = abs(sin(t * 8.5 + Double(i) * 0.7))
            return CGFloat(10 + (Double(band) * 0.75 + wave * 0.35) * envelope * 64)
        case .processing:
            let wave = abs(sin(t * 3.2 + Double(i) * 0.35))
            return CGFloat(8 + wave * envelope * 28)
        default:
            return CGFloat(6 + Double(band) * envelope * 12)
        }
    }

    private func barColors(_ i: Int) -> [Color] {
        let hues = [0.55, 0.62, 0.72, 0.85, 0.95, 0.08]
        let h = hues[i % hues.count]
        return [
            Color(hue: h, saturation: 0.75, brightness: 1),
            Color(hue: (h + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.65, brightness: 1)
        ]
    }

    private var glyph: String {
        switch phase {
        case .listening: return "ear.fill"
        case .processing: return "sparkles"
        case .speaking: return "speaker.wave.2.fill"
        case .error: return "exclamationmark.circle"
        case .idle: return "mic.fill"
        }
    }
}

/// Soft full-bleed mesh for Speak / Intelligence surfaces.
struct IntelligenceMeshBackground: View {
    @Environment(\.colorScheme) private var scheme
    @State private var drift = false

    var body: some View {
        ZStack {
            IntelligenceAtmosphere()
            FloatingIntelligenceDots(count: 6).opacity(0.18)

            Circle()
                .fill(NOCOAITheme.glowPrimary.opacity(scheme == .dark ? 0.2 : 0.12))
                .frame(width: 380, height: 380)
                .blur(radius: 90)
                .offset(x: drift ? 40 : -50, y: drift ? -120 : -40)

            Circle()
                .fill(NOCOAITheme.glowSecondary.opacity(scheme == .dark ? 0.16 : 0.1))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: drift ? -60 : 70, y: drift ? 180 : 80)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}

/// Horizontal rainbow shimmer line (NOCO accent).
struct IntelligenceShimmerLine: View {
    @State private var move = false

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        .clear,
                        Color(red: 0.4, green: 0.8, blue: 1),
                        Color(red: 0.7, green: 0.45, blue: 1),
                        Color(red: 0.4, green: 0.95, blue: 0.7),
                        .clear
                    ],
                    startPoint: move ? .leading : .trailing,
                    endPoint: move ? .trailing : .leading
                )
            )
            .frame(height: 2)
            .opacity(0.85)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    move = true
                }
            }
    }
}
