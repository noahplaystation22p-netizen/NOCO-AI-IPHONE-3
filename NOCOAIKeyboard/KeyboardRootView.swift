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
                    title: model.isProcessing ? "NOCO denkt…" : "Eingefügt"
                )
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: model.isProcessing)
        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: model.showIntelligenceBurst)
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
            if model.isProcessing {
                ProgressView()
                    .scaleEffect(0.65)
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

/// Apple Intelligence–style shimmer / glow while rewriting.
private struct IntelligenceRewriteOverlay: View {
    var phase: KeyboardViewModel.AnimationPhase
    var title: String

    @State private var spin = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.22))

            // Soft aurora mesh
            AngularGradient(
                colors: [
                    Color(red: 0.45, green: 0.7, blue: 1).opacity(0.55),
                    Color(red: 0.75, green: 0.45, blue: 1).opacity(0.5),
                    Color(red: 0.95, green: 0.55, blue: 0.75).opacity(0.45),
                    Color(red: 0.4, green: 0.85, blue: 0.95).opacity(0.5),
                    Color(red: 0.45, green: 0.7, blue: 1).opacity(0.55)
                ],
                center: .center
            )
            .blur(radius: 28)
            .opacity(pulse ? 0.85 : 0.45)
            .scaleEffect(pulse ? 1.08 : 0.92)
            .rotationEffect(.degrees(spin ? 360 : 0))

            // Sweeping highlight
            LinearGradient(
                colors: [
                    .clear,
                    Color.white.opacity(0.35),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 120)
            .rotationEffect(.degrees(-18))
            .offset(x: spin ? 160 : -160)
            .blur(radius: 8)

            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    Color(red: 0.4, green: 0.7, blue: 1),
                                    Color(red: 0.8, green: 0.45, blue: 1),
                                    Color(red: 0.4, green: 0.7, blue: 1)
                                ],
                                center: .center
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 36, height: 36)
                        .rotationEffect(.degrees(spin ? 360 : 0))

                    Image(systemName: phase == .success ? "checkmark" : "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: phase == .success)
                }

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 4)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial.opacity(0.85), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: Color(red: 0.5, green: 0.4, blue: 1).opacity(0.45), radius: 20, y: 4)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                spin = true
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
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
