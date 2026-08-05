import SwiftUI

/// Intense Apple-Intelligence / Siri-style rainbow orb for voice mode.
struct VoiceRainbowOrb: View {
    var phase: VoicePhase
    var level: CGFloat

    @State private var spinA = false
    @State private var spinB = false
    @State private var breathe = false
    @State private var pulse = false
    @State private var hueShift: Double = 0

    private var active: Bool {
        switch phase {
        case .listening, .processing, .speaking: return true
        default: return false
        }
    }

    private var intensity: CGFloat {
        switch phase {
        case .listening: return 0.55 + level * 0.5
        case .processing: return 0.82
        case .speaking: return 0.9
        default: return 0.38
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                outerBloom
                auroraVeil(t: t)
                rainbowRings
                waveformHalo
                coreOrb(t: t)
                sparkField(t: t)
                statusGlyph
            }
        }
        .frame(width: 340, height: 340)
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) { spinA = true }
            withAnimation(.linear(duration: 11).repeatForever(autoreverses: false)) { spinB = true }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) { breathe = true }
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private var outerBloom: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.45, green: 0.8, blue: 1).opacity(0.55 * intensity),
                            Color(red: 0.75, green: 0.35, blue: 1).opacity(0.28 * intensity),
                            Color(red: 1.0, green: 0.4, blue: 0.6).opacity(0.12 * intensity),
                            .clear
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 170
                    )
                )
                .frame(width: 340, height: 340)
                .scaleEffect(breathe ? 1.1 : 0.9)
                .blur(radius: 12)

            Circle()
                .fill(Color(red: 0.4, green: 0.95, blue: 0.7).opacity(0.18 * intensity))
                .frame(width: 220, height: 220)
                .blur(radius: 40)
                .offset(x: breathe ? 18 : -14, y: breathe ? -12 : 16)
        }
    }

    private func auroraVeil(t: Double) -> some View {
        AngularGradient(
            colors: rainbow(offset: t * 40),
            center: .center
        )
        .mask(
            Circle()
                .stroke(lineWidth: 48)
                .frame(width: 210, height: 210)
                .blur(radius: 18)
        )
        .opacity(0.35 + Double(intensity) * 0.35)
        .rotationEffect(.degrees(spinA ? 360 : 0))
        .blendMode(.plusLighter)
    }

    private var rainbowRings: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: rainbow(offset: Double(i) * 48),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: max(1.6, 4.2 - CGFloat(i) * 0.45), lineCap: .round)
                    )
                    .frame(width: 150 + CGFloat(i) * 26, height: 150 + CGFloat(i) * 26)
                    .rotationEffect(.degrees((i % 2 == 0 ? 1 : -1) * (spinA ? 360 : 0)))
                    .opacity(0.45 + Double(intensity) * 0.5)
                    .blur(radius: i == 0 ? 0.2 : 1.0)
                    .scaleEffect(1 + level * (phase == .listening ? 0.14 : 0.05) * CGFloat(5 - i) * 0.18)
            }

            // Dashed accent ring
            Circle()
                .stroke(
                    AngularGradient(colors: rainbow(offset: 120), center: .center),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 10])
                )
                .frame(width: 248, height: 248)
                .rotationEffect(.degrees(spinB ? -360 : 0))
                .opacity(0.7)
        }
    }

    private var waveformHalo: some View {
        HStack(spacing: 5) {
            ForEach(0..<9, id: \.self) { i in
                Capsule()
                    .fill(rainbow(offset: Double(i) * 28)[i % 7])
                    .frame(width: 4, height: barHeight(i))
                    .shadow(color: rainbow(offset: Double(i) * 28)[i % 7].opacity(0.8), radius: 6)
            }
        }
        .opacity(phase == .listening || phase == .speaking ? 0.95 : 0)
        .offset(y: 118)
        .animation(.easeOut(duration: 0.08), value: level)
    }

    private func coreOrb(t: Double) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.92),
                            Color(red: 0.55, green: 0.85, blue: 1).opacity(0.75),
                            Color(red: 0.6, green: 0.4, blue: 1).opacity(0.6),
                            Color(red: 0.2, green: 0.9, blue: 0.75).opacity(0.4),
                            Color(red: 1.0, green: 0.45, blue: 0.7).opacity(0.25)
                        ],
                        center: UnitPoint(x: 0.32 + 0.08 * sin(t), y: 0.28 + 0.06 * cos(t * 1.3)),
                        startRadius: 1,
                        endRadius: 78
                    )
                )
                .frame(width: 128, height: 128)
                .overlay(
                    Circle()
                        .stroke(
                            AngularGradient(colors: rainbow(offset: t * 60), center: .center),
                            lineWidth: 2.4
                        )
                        .rotationEffect(.degrees(spinB ? 360 : 0))
                )
                .shadow(color: Color(red: 0.35, green: 0.75, blue: 1).opacity(0.75 * intensity), radius: 30)
                .shadow(color: Color(red: 0.85, green: 0.35, blue: 1).opacity(0.5 * intensity), radius: 48)
                .shadow(color: Color(red: 1.0, green: 0.45, blue: 0.55).opacity(0.28 * intensity), radius: 64)
                .scaleEffect((pulse ? 1.04 : 0.97) * (1 + level * (phase == .listening ? 0.2 : 0.07)))
                .animation(.easeOut(duration: 0.07), value: level)

            // Specular highlight
            Ellipse()
                .fill(.white.opacity(0.55))
                .frame(width: 42, height: 18)
                .blur(radius: 2)
                .offset(x: -18, y: -28)
        }
    }

    private func sparkField(t: Double) -> some View {
        ForEach(0..<14, id: \.self) { i in
            let angle = Double(i) * (360.0 / 14.0) + t * (active ? 28 : 8)
            let radius = 92.0 + Double(i % 4) * 8 + Double(level) * 16
            Circle()
                .fill(rainbow(offset: Double(i) * 25)[i % 7])
                .frame(width: CGFloat(3 + i % 3), height: CGFloat(3 + i % 3))
                .offset(
                    x: CGFloat(cos(angle * .pi / 180) * radius),
                    y: CGFloat(sin(angle * .pi / 180) * radius)
                )
                .opacity(active ? (0.45 + 0.5 * sin(t * 3 + Double(i))) : 0.12)
                .blur(radius: 0.3)
                .shadow(color: rainbow(offset: Double(i) * 25)[i % 7], radius: 5)
        }
    }

    private var statusGlyph: some View {
        Image(systemName: glyph)
            .font(.system(size: 36, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.3), radius: 5)
            .symbolEffect(.pulse, options: .repeating, isActive: phase == .processing || phase == .listening)
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: phase == .speaking)
    }

    private func barHeight(_ i: Int) -> CGFloat {
        let base: CGFloat = phase == .speaking ? 18 : 10
        let wave = abs(sin(Double(i) * 0.9 + Double(level) * 8))
        return base + CGFloat(wave) * (22 + level * 28)
    }

    private var glyph: String {
        switch phase {
        case .listening: return "waveform"
        case .processing: return "sparkles"
        case .speaking: return "speaker.wave.2.fill"
        case .error: return "exclamationmark"
        case .idle: return "mic.fill"
        }
    }

    private func rainbow(offset: Double) -> [Color] {
        let hues: [Double] = [0.95, 0.08, 0.14, 0.35, 0.55, 0.68, 0.78, 0.95]
        return hues.map { h in
            Color(hue: (h + offset / 360).truncatingRemainder(dividingBy: 1), saturation: 0.85, brightness: 1)
        }
    }
}
