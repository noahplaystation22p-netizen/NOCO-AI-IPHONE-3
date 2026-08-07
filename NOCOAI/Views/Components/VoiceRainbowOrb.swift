import SwiftUI

/// Apple-Intelligence voice stage: living KI core + reactive rainbow waveform.
struct IntelligenceVoiceStage: View {
    var phase: VoicePhase
    var level: CGFloat
    var bands: [CGFloat] = Array(repeating: 0.15, count: 16)
    var assistantPhase: SpeakAssistantPhase = .idle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    @State private var breathe = false

    private var active: Bool {
        switch phase {
        case .listening, .processing, .speaking: return true
        default: return assistantPhase != .idle && assistantPhase != .error
        }
    }

    private var intensity: Double {
        switch resolvedEnergy {
        case .listening: return 0.45 + Double(level) * 0.55
        case .thinking, .webSearch: return 0.82
        case .speaking: return 0.85 + Double(level) * 0.15
        case .working, .vision: return 0.8
        case .idle, .success: return 0.35
        }
    }

    private var resolvedEnergy: NOCOIntelligenceEnergy {
        switch assistantPhase {
        case .webSearch: return .webSearch
        case .creatingImage, .agentWorking: return .working
        case .vision: return .vision
        case .thinking: return .thinking
        case .speaking: return .speaking
        case .listening: return .listening
        case .awaitingConfirm: return .thinking
        case .error, .idle: break
        }
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
            switch resolvedEnergy {
            case .listening: return 1.0 / 18.0
            case .speaking: return 1.0 / 22.0
            case .thinking, .webSearch: return 1.0 / 14.0
            case .working, .vision: return 1.0 / 12.0
            default: return 1.0 / 8.0
            }
        }()
        TimelineView(.animation(minimumInterval: interval)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                auroraField

                NOCOIntelligenceCore(
                    energy: resolvedEnergy,
                    size: .hero,
                    level: level,
                    systemImage: coreGlyph
                )
                .scaleEffect(1 + level * (phase == .listening ? 0.06 : 0.03))
                .opacity(0.94)

                softRings
                    .allowsHitTesting(false)

                if resolvedEnergy == .webSearch {
                    webSearchOrbit(t: t)
                        .allowsHitTesting(false)
                }

                centerWaveform(t: t)
                    .offset(y: 78)
            }
            .scaleEffect(active ? 1 + level * 0.04 : 1)
            .animation(.easeOut(duration: 0.08), value: level)
        }
        .frame(height: 280)
        .onAppear { startMotionIfNeeded() }
        .onChange(of: active) { _, _ in startMotionIfNeeded() }
        .onChange(of: resolvedEnergy) { _, _ in startMotionIfNeeded() }
    }

    private var coreGlyph: String? {
        switch resolvedEnergy {
        case .webSearch: return "globe"
        case .vision: return "eye.fill"
        case .working: return "sparkles"
        default: return nil
        }
    }

    private func webSearchOrbit(t: Double) -> some View {
        let angle = t * 110
        return ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(NOCORainbow.flow[i % NOCORainbow.flow.count].opacity(0.85))
                    .frame(width: 7, height: 7)
                    .offset(y: -92)
                    .rotationEffect(.degrees(angle + Double(i) * 120))
                    .blur(radius: 0.3)
            }
            Circle()
                .stroke(
                    AngularGradient(colors: NOCORainbow.flow.map { $0.opacity(0.55) }, center: .center),
                    style: StrokeStyle(lineWidth: 1.2, dash: [4, 6])
                )
                .frame(width: 196, height: 196)
                .rotationEffect(.degrees(-angle * 0.4))
                .opacity(0.55)
        }
    }

    private func startMotionIfNeeded() {
        guard !reduceMotion, active else {
            if !active { spin = false; breathe = false }
            return
        }
        let duration = resolvedEnergy.spinSeconds
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) { spin = true }
        withAnimation(.easeInOut(duration: resolvedEnergy == .listening ? 2.6 : 1.7).repeatForever(autoreverses: true)) {
            breathe = true
        }
    }

    private var auroraField: some View {
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            (resolvedEnergy == .webSearch ? NOCORainbow.blue : NOCORainbow.blue)
                                .opacity(0.38 * intensity),
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
                .fill((resolvedEnergy == .speaking ? NOCORainbow.pink : NOCORainbow.violet).opacity(0.14 * intensity))
                .frame(width: 270, height: 150)
                .blur(radius: 36)
                .offset(x: breathe ? 22 : -20, y: breathe ? -12 : 16)

            Ellipse()
                .fill(NOCORainbow.green.opacity(0.12 * intensity))
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

        switch resolvedEnergy {
        case .listening:
            return max(6, 10 + band * 72 * CGFloat(envelope) + level * 16)
        case .speaking:
            let wave = abs(sin(t * 8.5 + Double(i) * 0.7))
            return CGFloat(10 + (Double(band) * 0.75 + wave * 0.35) * envelope * 52)
        case .thinking, .webSearch:
            let wave = abs(sin(t * (resolvedEnergy == .webSearch ? 5.5 : 3.6) + Double(i) * 0.4))
            return CGFloat(8 + wave * envelope * (resolvedEnergy == .webSearch ? 34 : 26))
        case .working, .vision:
            let wave = abs(sin(t * 4.0 + Double(i) * 0.45))
            return CGFloat(8 + wave * envelope * 28)
        default:
            return CGFloat(6 + Double(band) * envelope * 12)
        }
    }

    private func barColors(_ i: Int) -> [Color] {
        let base = NOCORainbow.flow[i % (NOCORainbow.flow.count - 1)]
        let next = NOCORainbow.flow[(i + 1) % (NOCORainbow.flow.count - 1)]
        return [base, next]
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

// MARK: - Voice AI living transcript

/// Compact reactive bars for live listening (Voice UI, not Island).
struct SpeakVoiceMiniMeter: View {
    var level: CGFloat
    var bands: [CGFloat]

    var body: some View {
        let count = min(9, max(bands.count, 5))
        return HStack(alignment: .center, spacing: 3) {
            ForEach(0..<count, id: \.self) { i in
                meterBar(at: i)
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }

    private func meterBar(at i: Int) -> some View {
        let v: CGFloat = i < bands.count ? bands[i] : level
        let height = max(4, v * 16 + level * 4)
        return Capsule()
            .fill(
                LinearGradient(
                    colors: [NOCORainbow.blue, NOCORainbow.violet],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 3, height: height)
            .opacity(0.5 + Double(v) * 0.5)
    }
}

enum VoiceTranscriptStyle {
    case listening
    case thinking
    case speaking
    case idle
}

/// Animated transcript / reply text for NOCO Voice AI.
struct VoiceLivingTranscript: View {
    let text: String
    var style: VoiceTranscriptStyle
    var level: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glow = false

    var body: some View {
        styledText
            .multilineTextAlignment(.center)
            .shadow(color: glowColor.opacity(glowOpacity), radius: glowRadius)
            .scaleEffect(textScale)
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.18), value: text)
            .animation(.easeInOut(duration: 0.35), value: style)
            .onAppear { armGlow() }
            .onChange(of: style) { _, _ in armGlow() }
    }

    @ViewBuilder
    private var styledText: some View {
        switch style {
        case .speaking:
            Text(text)
                .font(.body.weight(.medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(0.95),
                            NOCORainbow.violet.opacity(0.88),
                            NOCORainbow.blue.opacity(0.82)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .thinking:
            Text(text)
                .font(.body.weight(.medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [NOCORainbow.blue, NOCORainbow.violet, NOCORainbow.pink],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        case .listening:
            Text(text)
                .font(.body)
                .foregroundStyle(Color.primary.opacity(0.92))
        case .idle:
            Text(text)
                .font(.body)
                .foregroundStyle(Color.primary.opacity(0.78))
        }
    }

    private var glowColor: Color {
        switch style {
        case .speaking: return NOCORainbow.violet
        case .listening: return NOCORainbow.blue
        case .thinking: return NOCORainbow.pink
        case .idle: return .clear
        }
    }

    private var glowOpacity: Double {
        if reduceMotion { return style == .speaking ? 0.2 : 0.08 }
        switch style {
        case .speaking: return glow ? 0.42 : 0.18
        case .listening: return 0.12 + Double(level) * 0.35
        case .thinking: return glow ? 0.35 : 0.15
        case .idle: return 0
        }
    }

    private var glowRadius: CGFloat {
        switch style {
        case .speaking: return glow ? 12 : 6
        case .listening: return 4 + level * 10
        case .thinking: return 10
        case .idle: return 0
        }
    }

    private var textScale: CGFloat {
        guard !reduceMotion else { return 1 }
        switch style {
        case .speaking: return glow ? 1.012 : 1
        case .listening: return 1 + level * 0.012
        default: return 1
        }
    }

    private func armGlow() {
        guard !reduceMotion else { return }
        glow = false
        let duration = style == .thinking ? 1.1 : 1.6
        withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
            glow = true
        }
    }
}
