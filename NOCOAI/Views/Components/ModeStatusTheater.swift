import SwiftUI

/// Subtle work status — short label + soft progress, no theater dots.
struct ModeStatusTheater: View {
    let phase: ModeWorkPhase
    let mode: AIMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0.2

    var body: some View {
        if phase != .idle {
            HStack(spacing: 12) {
                NOCOIntelligenceCore(
                    energy: phase == .done ? .success : .thinking,
                    size: .compact,
                    systemImage: nil
                )
                .frame(width: 40, height: 40)
                .overlay {
                    Text(phase.emoji)
                        .font(.system(size: 13))
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.78), value: phase)

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.caption.weight(.semibold))
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.28), value: phase)
                    Text(mode.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if phase != .done {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.08))
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: Array(NOCORainbow.flow.prefix(4)),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(10, geo.size.width * progress))
                            }
                        }
                        .frame(height: 3)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                AngularGradient(
                                    colors: NOCORainbow.flow.map { $0.opacity(0.35) },
                                    center: .center
                                ),
                                lineWidth: 1
                            )
                    )
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.98)))
            .onAppear { updateProgress() }
            .onChange(of: phase) { _, _ in updateProgress() }
        }
    }

    private var statusTitle: String {
        if mode.isImageCompose {
            switch phase {
            case .understanding, .analyzing: return "Formuliere Prompt"
            case .executing: return "Erstellt Bild"
            case .done: return "Fertig"
            case .idle: return phase.title
            }
        }
        return phase.title
    }

    private func updateProgress() {
        let target: CGFloat
        switch phase {
        case .understanding: target = 0.28
        case .analyzing: target = 0.52
        case .executing: target = 0.78
        case .done: target = 1
        case .idle: target = 0
        }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeInOut(duration: 0.55)) {
            progress = target
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
            Image(systemName: mode.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(mode.accentColor)
                .frame(width: 28, height: 28)
                .background(mode.accentColor.opacity(0.12), in: Circle())
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

        case .image:
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(mode.accentColor)
                .scaleEffect(tick ? 1.06 : 0.94)

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

