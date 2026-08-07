import SwiftUI

/// Apple-Intelligence voice stage: living KI core + reactive rainbow waveform.
struct IntelligenceVoiceStage: View {
    var phase: VoicePhase
    var level: CGFloat
    var bands: [CGFloat] = Array(repeating: 0.15, count: 16)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

    private var energy: NOCOIntelligenceEnergy {
        switch phase {
        case .listening: return .listening
        case .processing: return .thinking
        case .speaking: return .speaking
        case .error: return .idle
        case .idle: return .idle
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

                NOCOIntelligenceCore(
                    energy: energy,
                    size: .hero,
                    level: level
                )
                .scaleEffect(1 + level * (phase == .listening ? 0.06 : 0.03))
                .opacity(0.92)

                softRings
                    .allowsHitTesting(false)

                centerWaveform(t: t)
                    .offset(y: 78)

                statusSpark
            }
            .scaleEffect(active ? 1 + level * 0.04 : 1)
            .animation(.easeOut(duration: 0.08), value: level)
        }
        .frame(height: 280)
        .onAppear { startMotionIfNeeded() }
        .onChange(of: active) { _, _ in startMotionIfNeeded() }
    }

    private func startMotionIfNeeded() {
        guard !reduceMotion, active else {
            if !active { spin = false; breathe = false }
            return
        }
        withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) { spin = true }
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }
    }

    private var auroraField: some View {
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            NOCORainbow.blue.opacity(0.38 * intensity),
                            NOCORainbow.teal.opacity(0.16 * intensity),
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
                .fill(NOCORainbow.pink.opacity(0.14 * intensity))
                .frame(width: 270, height: 150)
                .blur(radius: 36)
                .offset(x: breathe ? 22 : -20, y: breathe ? -12 : 16)

            Ellipse()
                .fill(NOCORainbow.violet.opacity(0.12 * intensity))
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
                            colors: NOCORainbow.flow.map { $0.opacity(0.45) } + [.clear],
                            center: .center
                        ),
                        lineWidth: 1.1
                    )
                    .frame(width: 168 + CGFloat(i) * 36, height: 168 + CGFloat(i) * 36)
                    .rotationEffect(.degrees((i % 2 == 0 ? 1 : -1) * (spin ? 360 : 0)))
                    .opacity(0.28 + intensity * 0.3)
                    .scaleEffect(1 + level * (phase == .listening ? 0.14 : 0.05))
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
        .frame(height: 72)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(
                            AngularGradient(
                                colors: NOCORainbow.flow.map { $0.opacity(0.5 + Double(level) * 0.25) },
                                center: .center
                            ),
                            lineWidth: 1.2 + level * 1.2
                        )
                        .rotationEffect(.degrees(spin ? 360 : 0))
                )
                .shadow(color: NOCORainbow.blue.opacity(0.22 + Double(level) * 0.35), radius: 14 + level * 18)
        )
        .scaleEffect(1 + level * (phase == .listening ? 0.1 : 0.04))
        .animation(.easeOut(duration: 0.05), value: level)
        .animation(.easeOut(duration: 0.05), value: bands)
    }

    private var statusSpark: some View {
        Image(systemName: glyph)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 168)
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
            return max(6, 10 + band * 72 * CGFloat(envelope) + level * 16)
        case .speaking:
            let wave = abs(sin(t * 8.5 + Double(i) * 0.7))
            return CGFloat(10 + (Double(band) * 0.75 + wave * 0.35) * envelope * 52)
        case .processing:
            let wave = abs(sin(t * 3.2 + Double(i) * 0.35))
            return CGFloat(8 + wave * envelope * 24)
        default:
            return CGFloat(6 + Double(band) * envelope * 12)
        }
    }

    private func barColors(_ i: Int) -> [Color] {
        let base = NOCORainbow.flow[i % (NOCORainbow.flow.count - 1)]
        let next = NOCORainbow.flow[(i + 1) % (NOCORainbow.flow.count - 1)]
        return [base, next]
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        ZStack {
            IntelligenceAtmosphere()
            FloatingIntelligenceDots(count: 6).opacity(0.18)

            Circle()
                .fill(NOCORainbow.blue.opacity(scheme == .dark ? 0.18 : 0.1))
                .frame(width: 380, height: 380)
                .blur(radius: 90)
                .offset(x: drift ? 40 : -50, y: drift ? -120 : -40)

            Circle()
                .fill(NOCORainbow.violet.opacity(scheme == .dark ? 0.14 : 0.08))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: drift ? -60 : 70, y: drift ? 180 : 80)

            Circle()
                .fill(NOCORainbow.green.opacity(scheme == .dark ? 0.08 : 0.05))
                .frame(width: 220, height: 220)
                .blur(radius: 70)
                .offset(x: drift ? 30 : -40, y: drift ? 40 : -20)
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 11).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}

/// Horizontal rainbow shimmer line (NOCO accent).
struct IntelligenceShimmerLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var move = false

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [.clear] + NOCORainbow.flow + [.clear],
                    startPoint: move ? .leading : .trailing,
                    endPoint: move ? .trailing : .leading
                )
            )
            .frame(height: 2)
            .opacity(0.85)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true)) {
                    move = true
                }
            }
    }
}
