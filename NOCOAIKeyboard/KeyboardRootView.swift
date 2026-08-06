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

/// Rich Apple Intelligence–style rainbow aurora while rewriting into the field.
private struct IntelligenceRewriteOverlay: View {
    var phase: KeyboardViewModel.AnimationPhase
    var title: String

    @State private var spin = false
    @State private var pulse = false
    @State private var orbit = false
    @State private var sparkle = false
    @State private var hue = false
    @State private var ribbon = false

    private let rainbow: [Color] = [
        Color(red: 0.3, green: 0.85, blue: 1),
        Color(red: 0.4, green: 0.55, blue: 1),
        Color(red: 0.75, green: 0.4, blue: 1),
        Color(red: 0.95, green: 0.4, blue: 0.75),
        Color(red: 1.0, green: 0.65, blue: 0.35),
        Color(red: 0.45, green: 0.95, blue: 0.7),
        Color(red: 0.3, green: 0.85, blue: 1)
    ]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black.opacity(0.18))

            // Full rainbow mesh
            AngularGradient(colors: rainbow, center: .center)
                .blur(radius: 38)
                .opacity(pulse ? 0.7 : 0.38)
                .scaleEffect(pulse ? 1.2 : 0.92)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .hueRotation(.degrees(hue ? 24 : -16))
                .blendMode(.plusLighter)

            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(rainbow[i].opacity(0.5))
                    .frame(width: 120 + CGFloat(i * 28), height: 120 + CGFloat(i * 28))
                    .blur(radius: 30)
                    .offset(
                        x: orbit ? CGFloat(30 - i * 10) : CGFloat(-26 + i * 9),
                        y: pulse ? CGFloat(-20 + i * 5) : CGFloat(18 - i * 4)
                    )
                    .blendMode(.plusLighter)
            }

            // Sweeping ribbon
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.7), rainbow[2].opacity(0.5), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 260, height: 64)
                .rotationEffect(.degrees(-18))
                .offset(x: ribbon ? 140 : -140)
                .blur(radius: 8)
                .opacity(0.85)

            ForEach(0..<8, id: \.self) { i in
                Image(systemName: "sparkle")
                    .font(.system(size: CGFloat(7 + i % 4 * 2), weight: .bold))
                    .foregroundStyle(rainbow[i % 6].opacity(sparkle ? 1 : 0.2))
                    .offset(
                        x: CGFloat([-78, -48, -10, 28, 58, 82, 12, -30][i]),
                        y: CGFloat([-55, 38, -70, 22, -28, 48, 62, -12][i]) * (sparkle ? 1.08 : 0.88)
                    )
                    .scaleEffect(sparkle ? 1.2 : 0.65)
            }

            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.4), rainbow[2].opacity(0.25), .clear],
                                center: .center,
                                startRadius: 2,
                                endRadius: 40
                            )
                        )
                        .frame(width: 78, height: 78)
                        .scaleEffect(pulse ? 1.14 : 0.88)

                    Circle()
                        .stroke(AngularGradient(colors: rainbow, center: .center), lineWidth: 4)
                        .frame(width: 52, height: 52)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .shadow(color: rainbow[2].opacity(0.85), radius: 14)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.6), rainbow[1].opacity(0.2), .clear],
                                center: .center,
                                startRadius: 1,
                                endRadius: 20
                            )
                        )
                        .frame(width: 40, height: 40)
                        .scaleEffect(pulse ? 1.08 : 0.92)

                    Image(systemName: phase == .success ? "checkmark" : (phase == .writing ? "wand.and.stars" : "sparkles"))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: phase)
                        .symbolEffect(.pulse, options: .repeating, value: phase == .thinking || phase == .writing)
                }

                if phase == .thinking, !title.isEmpty {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .shadow(color: .black.opacity(0.35), radius: 6)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .padding(.horizontal, phase == .thinking ? 22 : 18)
            .padding(.vertical, 14)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.9))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(AngularGradient(colors: rainbow, center: .center), lineWidth: 1.5)
                    )
                    .shadow(color: rainbow[2].opacity(0.55), radius: 22, y: 6)
            )
            .animation(.spring(response: 0.4, dampingFraction: 0.82), value: phase)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) { orbit = true }
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) { sparkle = true }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) { hue = true }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { ribbon = true }
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
