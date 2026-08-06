import SwiftUI

struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardViewModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            aiHeader
            aiToolbar
            statusBar
            KeyboardLayoutView(model: model)
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
        }
        .padding(.top, 4)
        .background(keyboardBackground)
        .overlay {
            if model.isProcessing || model.showIntelligenceBurst {
                IntelligenceRewriteOverlay(
                    phase: model.animationPhase,
                    title: model.overlayTitle
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.94)),
                    removal: .opacity.combined(with: .scale(scale: 1.02))
                ))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: model.isProcessing)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: model.showIntelligenceBurst)
        .animation(.easeInOut(duration: 0.22), value: model.animationPhase)
    }

    // MARK: - Header

    private var aiHeader: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.45, green: 0.72, blue: 1.0),
                                Color(red: 0.55, green: 0.88, blue: 0.92)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 18, height: 18)
                    .opacity(0.9)
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text("NOCO")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(scheme == .dark ? .white.opacity(0.92) : Color(red: 0.12, green: 0.14, blue: 0.2))

            Text("AI")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(red: 0.35, green: 0.55, blue: 1.0).opacity(scheme == .dark ? 0.28 : 0.14))
                )
                .foregroundStyle(Color(red: 0.35, green: 0.55, blue: 1.0))

            Spacer(minLength: 0)

            if model.isProcessing {
                Text("arbeitet…")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 2)
    }

    // MARK: - Toolbar chips

    private var aiToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(model.toolbarChips) { chip in
                    Button {
                        model.runChip(chip)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: chip.systemImage)
                                .font(.system(size: 11, weight: .semibold))
                            Text(chip.title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(chipBackground(for: chip))
                        .foregroundStyle(chipForeground(for: chip))
                    }
                    .buttonStyle(SoftPressStyle())
                    .disabled(model.isProcessing)
                    .opacity(model.isProcessing ? 0.5 : 1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .stroke(statusColor.opacity(0.35), lineWidth: 3)
                        .blur(radius: 0.5)
                )
            Text(model.statusLine)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
            if !model.isConfigured {
                Button("App öffnen") {
                    model.openAppForSync()
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.32, green: 0.52, blue: 0.98))
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(scheme == .dark
                      ? Color.white.opacity(0.05)
                      : Color.white.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(scheme == .dark
                                ? Color.white.opacity(0.08)
                                : Color.black.opacity(0.05), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    private var keyboardBackground: some View {
        ZStack {
            (scheme == .dark
             ? Color(red: 0.09, green: 0.095, blue: 0.12)
             : Color(red: 0.80, green: 0.82, blue: 0.86))

            // Soft AI wash — cool cyan/silver, not purple
            LinearGradient(
                colors: [
                    Color(red: 0.45, green: 0.7, blue: 1.0).opacity(scheme == .dark ? 0.12 : 0.18),
                    Color(red: 0.55, green: 0.9, blue: 0.88).opacity(scheme == .dark ? 0.06 : 0.1),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(scheme == .dark ? 0.04 : 0.35),
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
        if model.isProcessing { return Color(red: 0.4, green: 0.7, blue: 1) }
        if model.lastError != nil { return .red }
        return Color(red: 0.3, green: 0.84, blue: 0.58)
    }

    @ViewBuilder
    private func chipBackground(for chip: KeyboardToolbarChip) -> some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        ZStack {
            if chip.isPrimary {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.34, green: 0.56, blue: 1.0),
                            Color(red: 0.42, green: 0.78, blue: 0.95)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            } else if chip.isAnswer {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.22, green: 0.72, blue: 0.68),
                            Color(red: 0.38, green: 0.62, blue: 0.95)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            } else if chip.isCustom {
                shape.fill(.ultraThinMaterial)
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.4, green: 0.7, blue: 1.0).opacity(0.28),
                            Color(red: 0.5, green: 0.9, blue: 0.85).opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                shape.stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.45, green: 0.75, blue: 1.0).opacity(0.7),
                            Color(red: 0.55, green: 0.9, blue: 0.85).opacity(0.45)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill(scheme == .dark
                           ? Color.white.opacity(0.06)
                           : Color.white.opacity(0.55))
                shape.stroke(
                    scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06),
                    lineWidth: 0.5
                )
            }
        }
    }

    private func chipForeground(for chip: KeyboardToolbarChip) -> Color {
        if chip.isPrimary || chip.isAnswer { return .white }
        if chip.isCustom {
            return scheme == .dark ? Color(red: 0.75, green: 0.9, blue: 1.0) : Color(red: 0.2, green: 0.38, blue: 0.72)
        }
        return .primary
    }
}

// MARK: - Rewrite overlay (clean Apple Intelligence–style aurora)

private struct IntelligenceRewriteOverlay: View {
    var phase: KeyboardViewModel.AnimationPhase
    var title: String

    @State private var spin = false
    @State private var pulse = false
    @State private var drift = false

    private let aurora: [Color] = [
        Color(red: 0.45, green: 0.78, blue: 1.0),
        Color(red: 0.55, green: 0.88, blue: 0.92),
        Color(red: 0.7, green: 0.78, blue: 1.0),
        Color(red: 0.5, green: 0.92, blue: 0.82),
        Color(red: 0.45, green: 0.78, blue: 1.0)
    ]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black.opacity(0.14))

            AngularGradient(colors: aurora, center: .center)
                .blur(radius: 42)
                .opacity(pulse ? 0.55 : 0.28)
                .scaleEffect(pulse ? 1.12 : 0.94)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .blendMode(.plusLighter)

            Circle()
                .fill(aurora[0].opacity(0.35))
                .frame(width: 140, height: 140)
                .blur(radius: 36)
                .offset(x: drift ? 28 : -22, y: pulse ? -16 : 14)
                .blendMode(.plusLighter)

            Circle()
                .fill(aurora[3].opacity(0.3))
                .frame(width: 110, height: 110)
                .blur(radius: 30)
                .offset(x: drift ? -24 : 20, y: pulse ? 18 : -12)
                .blendMode(.plusLighter)

            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(
                            AngularGradient(colors: aurora, center: .center),
                            lineWidth: 2.5
                        )
                        .frame(width: 46, height: 46)
                        .rotationEffect(.degrees(spin ? 360 : 0))

                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 34, height: 34)

                    Image(systemName: phase == .success
                          ? "checkmark"
                          : (phase == .writing ? "wand.and.stars" : "sparkles"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: phase)
                        .symbolEffect(.pulse, options: .repeating, value: phase == .thinking || phase == .writing)
                }

                if phase == .thinking, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                        .shadow(color: .black.opacity(0.25), radius: 4)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, phase == .thinking ? 20 : 16)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.92))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.55),
                                        aurora[0].opacity(0.45),
                                        aurora[3].opacity(0.35)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .animation(.spring(response: 0.38, dampingFraction: 0.84), value: phase)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 4.2).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

private struct SoftPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.11), value: configuration.isPressed)
    }
}
