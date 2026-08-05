import SwiftUI

/// Apple-Intelligence voice stage: soft aurora + thin rings + reactive waveform — not a fat orb.
struct IntelligenceVoiceStage: View {
    var phase: VoicePhase
    var level: CGFloat

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
        case .listening: return 0.55 + Double(level) * 0.45
        case .processing: return 0.8
        case .speaking: return 0.9
        case .error: return 0.35
        case .idle: return 0.4
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                auroraField
                softRings
                centerWaveform(t: t)
                statusSpark
            }
        }
        .frame(height: 280)
        .onAppear {
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }
        }
    }

    private var auroraField: some View {
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.45, green: 0.78, blue: 1).opacity(0.34 * intensity),
                            Color(red: 0.65, green: 0.45, blue: 1).opacity(0.18 * intensity),
                            .clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 160
                    )
                )
                .frame(width: 340, height: 220)
                .blur(radius: 28)
                .scaleEffect(breathe ? 1.06 : 0.94)

            Ellipse()
                .fill(Color(red: 0.35, green: 0.92, blue: 0.75).opacity(0.14 * intensity))
                .frame(width: 260, height: 140)
                .blur(radius: 36)
                .offset(x: breathe ? 20 : -18, y: breathe ? -10 : 14)

            Ellipse()
                .fill(Color(red: 1.0, green: 0.55, blue: 0.7).opacity(0.1 * intensity))
                .frame(width: 200, height: 120)
                .blur(radius: 30)
                .offset(x: breathe ? -24 : 16, y: 20)
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
                    .scaleEffect(1 + level * (phase == .listening ? 0.06 : 0.02))
            }
        }
    }

    private func centerWaveform(t: Double) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<21, id: \.self) { i in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: barColors(i),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 4, height: barHeight(i, t: t))
                    .shadow(color: barColors(i)[0].opacity(0.55), radius: active ? 5 : 0)
            }
        }
        .frame(height: 72)
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    Color(red: 0.4, green: 0.8, blue: 1).opacity(0.55),
                                    Color(red: 0.7, green: 0.4, blue: 1).opacity(0.35),
                                    Color(red: 0.4, green: 0.95, blue: 0.7).opacity(0.4),
                                    Color(red: 0.4, green: 0.8, blue: 1).opacity(0.55)
                                ],
                                center: .center
                            ),
                            lineWidth: 1.2
                        )
                        .rotationEffect(.degrees(spin ? 360 : 0))
                )
                .shadow(color: Color(red: 0.45, green: 0.7, blue: 1).opacity(0.28 * intensity), radius: 22)
        )
        .scaleEffect(phase == .listening ? 1 + level * 0.04 : 1)
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
        let mid = abs(Double(i) - 10.0)
        let envelope = max(0.15, 1.0 - mid / 12.0)
        switch phase {
        case .listening:
            let wave = abs(sin(t * 10 + Double(i) * 0.55))
            return CGFloat(10 + (wave * 0.45 + Double(level) * 0.7) * envelope * 52)
        case .speaking:
            let wave = abs(sin(t * 8.5 + Double(i) * 0.7))
            return CGFloat(12 + wave * envelope * 44)
        case .processing:
            let wave = abs(sin(t * 3.2 + Double(i) * 0.35))
            return CGFloat(8 + wave * envelope * 22)
        default:
            let wave = abs(sin(t * 1.4 + Double(i) * 0.25))
            return CGFloat(6 + wave * envelope * 10)
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
            FloatingIntelligenceDots(count: 16).opacity(0.4)

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

/// Horizontal rainbow shimmer line (Apple Intelligence accent).
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
