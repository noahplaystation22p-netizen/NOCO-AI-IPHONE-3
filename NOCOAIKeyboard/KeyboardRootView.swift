import SwiftUI

struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardViewModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            aiToolbar
            statusBar
            KeyboardLayoutView(model: model)
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
        }
        .padding(.top, 6)
        .background(keyboardBackground)
        .overlay {
            if model.isProcessing || model.showIntelligenceBurst {
                IntelligenceRewriteOverlay(
                    phase: model.animationPhase,
                    title: model.overlayTitle
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.9)),
                    removal: .opacity.combined(with: .scale(scale: 1.04))
                ))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: model.isProcessing)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: model.showIntelligenceBurst)
        .animation(.easeInOut(duration: 0.25), value: model.animationPhase)
    }

    private var aiToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(KeyboardAIAction.allCases) { action in
                    Button {
                        model.run(action)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: action.systemImage)
                                .font(.caption.weight(.semibold))
                            Text(action.title)
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(chipFill(for: action))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(chipStroke, lineWidth: 1)
                                )
                                .shadow(
                                    color: action.isPrimary
                                        ? Color(red: 0.35, green: 0.45, blue: 1).opacity(0.4)
                                        : .clear,
                                    radius: 8, y: 2
                                )
                        )
                        .foregroundStyle(chipForeground(for: action))
                    }
                    .buttonStyle(SoftPressStyle())
                    .disabled(model.isProcessing)
                    .opacity(model.isProcessing ? 0.55 : 1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .shadow(color: statusColor.opacity(0.75), radius: 3)
            Text(model.statusLine)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
            if !model.isConfigured {
                Button("App öffnen") {
                    model.openAppForSync()
                }
                .font(.caption2.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    private var keyboardBackground: some View {
        ZStack {
            (scheme == .dark
             ? Color(red: 0.11, green: 0.11, blue: 0.12)
             : Color(red: 0.82, green: 0.83, blue: 0.85))
            LinearGradient(
                colors: [
                    Color.white.opacity(scheme == .dark ? 0.05 : 0.4),
                    .clear
                ],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }

    private var statusColor: Color {
        if !model.hasFullAccess || !model.isConfigured { return .orange }
        if model.isProcessing { return Color(red: 0.35, green: 0.65, blue: 1) }
        if model.lastError != nil { return .red }
        return Color(red: 0.25, green: 0.82, blue: 0.5)
    }

    private func chipFill(for action: KeyboardAIAction) -> some ShapeStyle {
        if action.isPrimary {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.32, green: 0.52, blue: 1),
                        Color(red: 0.52, green: 0.42, blue: 0.95)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }

    private func chipForeground(for action: KeyboardAIAction) -> Color {
        action.isPrimary ? .white : .primary
    }

    private var chipStroke: Color {
        scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
    }
}

/// Rich Apple Intelligence–style aurora while rewriting into the field.
private struct IntelligenceRewriteOverlay: View {
    var phase: KeyboardViewModel.AnimationPhase
    var title: String

    @State private var spin = false
    @State private var pulse = false
    @State private var orbit = false
    @State private var sparkle = false

    var body: some View {
        ZStack {
            // Dim glass
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black.opacity(0.12))

            // Multi-layer aurora
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(blobColor(i).opacity(0.55))
                    .frame(width: 140 + CGFloat(i * 30), height: 140 + CGFloat(i * 30))
                    .blur(radius: 36)
                    .offset(
                        x: orbit ? CGFloat(28 - i * 12) : CGFloat(-24 + i * 10),
                        y: pulse ? CGFloat(-18 + i * 6) : CGFloat(16 - i * 5)
                    )
                    .blendMode(.plusLighter)
            }

            AngularGradient(
                colors: [
                    Color(red: 0.35, green: 0.75, blue: 1),
                    Color(red: 0.55, green: 0.4, blue: 1),
                    Color(red: 0.95, green: 0.45, blue: 0.75),
                    Color(red: 0.4, green: 0.9, blue: 0.85),
                    Color(red: 0.35, green: 0.75, blue: 1)
                ],
                center: .center
            )
            .blur(radius: 40)
            .opacity(pulse ? 0.55 : 0.28)
            .scaleEffect(pulse ? 1.15 : 0.88)
            .rotationEffect(.degrees(spin ? 360 : 0))

            // Light sweep
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.55), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 220, height: 70)
                .rotationEffect(.degrees(-22))
                .offset(x: spin ? 130 : -130)
                .blur(radius: 10)
                .opacity(0.7)

            // Floating sparkles
            ForEach(0..<6, id: \.self) { i in
                Image(systemName: "sparkle")
                    .font(.system(size: CGFloat(8 + i % 3 * 3), weight: .bold))
                    .foregroundStyle(.white.opacity(sparkle ? 0.95 : 0.25))
                    .offset(
                        x: CGFloat([-70, -40, 10, 50, 75, -15][i]),
                        y: CGFloat([-50, 35, -65, 20, -30, 55][i]) * (sparkle ? 1.05 : 0.9)
                    )
                    .scaleEffect(sparkle ? 1.15 : 0.7)
            }

            VStack(spacing: 10) {
                ZStack {
                    // Soft bloom behind glyph
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.35),
                                    Color(red: 0.55, green: 0.45, blue: 1).opacity(0.18),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 2,
                                endRadius: 36
                            )
                        )
                        .frame(width: 72, height: 72)
                        .scaleEffect(pulse ? 1.12 : 0.9)

                    // Outer ring
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    Color(red: 0.4, green: 0.8, blue: 1),
                                    Color(red: 0.85, green: 0.45, blue: 1),
                                    Color(red: 0.95, green: 0.6, blue: 0.8),
                                    Color(red: 0.4, green: 0.9, blue: 0.85),
                                    Color(red: 0.4, green: 0.8, blue: 1)
                                ],
                                center: .center
                            ),
                            lineWidth: 3.5
                        )
                        .frame(width: 48, height: 48)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .shadow(color: Color(red: 0.55, green: 0.45, blue: 1).opacity(0.8), radius: 12)

                    // Inner glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.55),
                                    Color(red: 0.5, green: 0.45, blue: 1).opacity(0.2),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 2,
                                endRadius: 22
                            )
                        )
                        .frame(width: 40, height: 40)
                        .scaleEffect(pulse ? 1.08 : 0.92)

                    Image(systemName: phase == .success ? "checkmark" : (phase == .writing ? "wand.and.stars" : "sparkles"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: phase)
                        .symbolEffect(.pulse, options: .repeating, value: phase == .thinking || phase == .writing)
                }

                // Minimal label only while thinking — writing/success stay visual-only
                if phase == .thinking, !title.isEmpty {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.35), radius: 6)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .padding(.horizontal, phase == .thinking ? 22 : 18)
            .padding(.vertical, 14)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.88))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.6),
                                        Color(red: 0.6, green: 0.5, blue: 1).opacity(0.4),
                                        Color.white.opacity(0.18)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                    )
                    .shadow(color: Color(red: 0.45, green: 0.4, blue: 1).opacity(0.55), radius: 24, y: 6)
            )
            .animation(.spring(response: 0.4, dampingFraction: 0.82), value: phase)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) { orbit = true }
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { sparkle = true }
        }
    }

    private func blobColor(_ i: Int) -> Color {
        switch i {
        case 0: return Color(red: 0.35, green: 0.7, blue: 1)
        case 1: return Color(red: 0.7, green: 0.4, blue: 1)
        default: return Color(red: 0.95, green: 0.5, blue: 0.75)
        }
    }
}

private struct SoftPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
