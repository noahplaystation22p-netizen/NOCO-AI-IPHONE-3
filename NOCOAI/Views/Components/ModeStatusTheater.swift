import SwiftUI

/// Per-mode animated identity glyph — scanner, code, ink, study cards, creative bloom, agent core.
struct ModeIdentityGlyph: View {
    let mode: AIMode
    var size: CGFloat = 28
    var active: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tick = false

    var body: some View {
        ZStack {
            // Rainbow glass aura
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            mode.accentColor,
                            Color(red: 0.45, green: 0.72, blue: 1.0),
                            Color(red: 0.98, green: 0.55, blue: 0.85),
                            mode.accentColor
                        ],
                        center: .center
                    )
                )
                .frame(width: size, height: size)
                .blur(radius: active ? size * 0.22 : size * 0.12)
                .opacity(0.9)
                .rotationEffect(.degrees(tick && active && !reduceMotion ? 360 : 0))

            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: size * 0.78, height: size * 0.78)
                .overlay(
                    Circle()
                        .stroke(mode.accentColor.opacity(0.45), lineWidth: 1)
                )

            modeOverlay
        }
        .onAppear {
            guard active, !reduceMotion else { return }
            withAnimation(.linear(duration: mode == .vision ? 2.8 : 5.5).repeatForever(autoreverses: false)) {
                tick = true
            }
        }
    }

    @ViewBuilder
    private var modeOverlay: some View {
        switch mode {
        case .vision:
            ZStack {
                Image(systemName: "eye.circle.fill")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(mode.accentColor)
                Capsule()
                    .fill(LinearGradient(colors: [.clear, mode.accentColor, .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(width: size * 0.55, height: 2)
                    .offset(y: tick ? size * 0.16 : -size * 0.16)
                    .opacity(active ? 0.95 : 0.4)
            }
            .frame(width: size * 0.72, height: size * 0.72)
            .clipShape(Circle())

        case .developer:
            ZStack {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(mode.accentColor)
                Text("{}")
                    .font(.system(size: size * 0.18, weight: .bold, design: .monospaced))
                    .foregroundStyle(mode.accentColor.opacity(0.55))
                    .offset(x: tick ? 4 : -4, y: tick ? -3 : 3)
            }

        case .writing:
            ZStack {
                Image(systemName: "pencil.line")
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(mode.accentColor)
                    .offset(x: tick ? 2 : -2)
                Capsule()
                    .fill(mode.accentColor.opacity(0.35))
                    .frame(width: size * 0.42, height: 2)
                    .offset(y: size * 0.22)
                    .scaleEffect(x: tick ? 1 : 0.55, anchor: .leading)
            }

        case .study:
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(mode.accentColor.opacity(0.35))
                    .frame(width: size * 0.16, height: size * 0.28)
                    .offset(y: tick ? -2 : 2)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(mode.accentColor.opacity(0.7))
                    .frame(width: size * 0.16, height: size * 0.34)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(mode.accentColor.opacity(0.45))
                    .frame(width: size * 0.16, height: size * 0.24)
                    .offset(y: tick ? 2 : -2)
            }

        case .creative:
            Image(systemName: "paintpalette.fill")
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(mode.accentColor)
                .scaleEffect(tick ? 1.08 : 0.92)
                .rotationEffect(.degrees(tick ? 12 : -8))

        case .agent:
            Image(systemName: "cpu.fill")
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(mode.accentColor)
                .symbolEffect(.pulse, options: .repeating, isActive: active && !reduceMotion)

        default:
            Image(systemName: mode.systemImage)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(mode.accentColor)
        }
    }
}

/// Floating micro-particles for analyzing phase.
struct ModeParticleField: View {
    let color: Color
    var count: Int = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<count, id: \.self) { i in
                    Circle()
                        .fill(color.opacity(0.7))
                        .frame(width: CGFloat(2 + i % 3), height: CGFloat(2 + i % 3))
                        .position(
                            x: CGFloat((i * 37) % max(Int(geo.size.width), 1)),
                            y: CGFloat((i * 53) % max(Int(geo.size.height), 1))
                        )
                        .offset(y: (!reduceMotion && on) ? -10 : 0)
                        .opacity((!reduceMotion && on) ? 0.95 : 0.35)
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 1.2 + Double(i % 4) * 0.2).repeatForever(autoreverses: true),
                            value: on
                        )
                }
            }
        }
        .onAppear { on = true }
        .allowsHitTesting(false)
    }
}

/// Premium mode status theater — Verstehen → Analysieren → Ausführen → Fertig.
struct ModeStatusTheater: View {
    let phase: ModeWorkPhase
    let mode: AIMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var progress: CGFloat = 0.15

    var body: some View {
        if phase != .idle {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    ZStack {
                        ModeIdentityGlyph(mode: mode, size: 40, active: phase != .done)
                        if phase == .analyzing {
                            ModeParticleField(color: mode.accentColor)
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                        }
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(phaseEmoji)
                            Text(phase.title)
                                .font(.caption.weight(.bold))
                        }
                        Text("\(mode.label) · \(mode.modelHint)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if phase == .executing || phase == .analyzing {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.08))
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [mode.accentColor, mode.accentColor.opacity(0.5)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(8, geo.size.width * progress))
                                }
                            }
                            .frame(height: 4)
                        }
                    }

                    Spacer(minLength: 0)
                    phaseDots
                }

                if phase == .done {
                    Text("Bereit für den nächsten Schritt")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(mode.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [mode.accentColor.opacity(0.55), mode.accentColor.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: mode.accentColor.opacity(phase == .done ? 0.35 : 0.18), radius: phase == .done ? 16 : 10, y: 3)
            }
            .scaleEffect(pulse && phase == .understanding ? 1.015 : 1)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .onAppear { startMotion() }
            .onChange(of: phase) { _, _ in startMotion() }
        }
    }

    private var phaseEmoji: String {
        switch phase {
        case .understanding: return "🧠"
        case .analyzing: return "🔎"
        case .executing: return "⚙️"
        case .done: return "✅"
        case .idle: return ""
        }
    }

    private var phaseDots: some View {
        HStack(spacing: 5) {
            ForEach([ModeWorkPhase.understanding, .analyzing, .executing, .done], id: \.rawValue) { p in
                Circle()
                    .fill(dotColor(p))
                    .frame(width: 7, height: 7)
                    .scaleEffect(phase == p ? 1.35 : 1)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: phase)
            }
        }
    }

    private func dotColor(_ p: ModeWorkPhase) -> Color {
        let order: [ModeWorkPhase] = [.understanding, .analyzing, .executing, .done]
        guard let pi = order.firstIndex(of: p), let ci = order.firstIndex(of: phase) else {
            return Color.primary.opacity(0.15)
        }
        if pi < ci { return mode.accentColor.opacity(0.85) }
        if pi == ci { return mode.accentColor }
        return Color.primary.opacity(0.15)
    }

    private func startMotion() {
        guard !reduceMotion else {
            progress = phase == .done ? 1 : 0.4
            return
        }
        withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
            pulse = true
        }
        switch phase {
        case .understanding:
            progress = 0.22
        case .analyzing:
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                progress = 0.55
            }
        case .executing:
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                progress = 0.82
            }
        case .done:
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                progress = 1
            }
        case .idle:
            progress = 0
        }
    }
}

/// Compact recommendation chip under the mode picker.
struct ModeRecommendationChip: View {
    let mode: AIMode
    let reason: String
    let onApply: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ModeIdentityGlyph(mode: mode, size: 32, active: true)
            VStack(alignment: .leading, spacing: 1) {
                Text(reason)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                Text("Bereich wechseln")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("OK") {
                HapticService.modeChange()
                onApply()
            }
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(mode.accentColor.opacity(0.9), in: Capsule())
            .foregroundStyle(.white)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(mode.accentColor.opacity(0.35), lineWidth: 1)
        )
    }
}
