import SwiftUI

struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardViewModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            aiHeader
            aiToolbar
            if model.showAskPanel {
                askPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            statusBar
            KeyboardLayoutView(model: model)
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
        }
        .padding(.top, 4)
        .background(keyboardBackground)
        .overlay {
            if model.isProcessing || model.showIntelligenceBurst || model.isAsking {
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
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: model.showAskPanel)
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
                .foregroundStyle(.white.opacity(0.92))

            Text("AI")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(red: 0.35, green: 0.55, blue: 1.0).opacity(0.28))
                )
                .foregroundStyle(Color(red: 0.55, green: 0.78, blue: 1.0))

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
                Button {
                    model.toggleAskPanel()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.left.and.text.bubble.right.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Fragen")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: model.showAskPanel
                                    ? [Color(red: 0.35, green: 0.75, blue: 1), Color(red: 0.45, green: 0.55, blue: 1)]
                                    : [Color(red: 0.2, green: 0.45, blue: 0.95), Color(red: 0.35, green: 0.7, blue: 0.9)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(SoftPressStyle())

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
                    .disabled(model.isProcessing || model.isAsking)
                    .opacity(model.isProcessing || model.isAsking ? 0.5 : 1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
    }

    private var askPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Frag NOCO AI…", text: $model.askDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color(red: 0.4, green: 0.75, blue: 1).opacity(0.35), lineWidth: 1)
                            )
                    )
                    .foregroundStyle(.white)
                    .disabled(model.isAsking)

                Button {
                    model.sendAsk()
                } label: {
                    Image(systemName: model.isAsking ? "ellipsis" : "arrow.up.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(
                            model.askDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.white.opacity(0.35)
                            : Color(red: 0.45, green: 0.8, blue: 1)
                        )
                }
                .disabled(
                    model.isAsking ||
                    model.askDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            if !model.askReply.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.askReply)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Einfügen") {
                            model.insertAskReply()
                        }
                        .font(.caption.weight(.bold))
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.35, green: 0.6, blue: 1))
                        .controlSize(.mini)

                        Button("Schließen") {
                            model.toggleAskPanel()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
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
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    private var keyboardBackground: some View {
        ZStack {
            // Always a bit darker / premium AI chrome
            Color(red: 0.07, green: 0.075, blue: 0.1)

            LinearGradient(
                colors: [
                    Color(red: 0.25, green: 0.45, blue: 0.95).opacity(0.22),
                    Color(red: 0.2, green: 0.7, blue: 0.85).opacity(0.12),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Soft moving wash
            Circle()
                .fill(Color(red: 0.35, green: 0.7, blue: 1).opacity(0.12))
                .frame(width: 220, height: 220)
                .blur(radius: 50)
                .offset(x: -80, y: -40)

            Circle()
                .fill(Color(red: 0.4, green: 0.9, blue: 0.85).opacity(0.08))
                .frame(width: 180, height: 180)
                .blur(radius: 40)
                .offset(x: 100, y: 60)
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
            } else if chip.isComplete {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.3, green: 0.7, blue: 0.95),
                            Color(red: 0.45, green: 0.85, blue: 0.8)
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
                shape.fill(Color.white.opacity(0.08))
                shape.stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            }
        }
    }

    private func chipForeground(for chip: KeyboardToolbarChip) -> Color {
        if chip.isPrimary || chip.isAnswer || chip.isComplete { return .white }
        if chip.isCustom {
            return Color(red: 0.75, green: 0.9, blue: 1.0)
        }
        return .white.opacity(0.9)
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
                .fill(.black.opacity(0.22))

            AngularGradient(colors: aurora, center: .center)
                .blur(radius: 42)
                .opacity(pulse ? 0.62 : 0.32)
                .scaleEffect(pulse ? 1.16 : 0.92)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .blendMode(.plusLighter)

            Capsule()
                .fill(LinearGradient(
                    colors: [.clear, .white.opacity(0.55), aurora[2].opacity(0.4), .clear],
                    startPoint: .leading, endPoint: .trailing
                ))
                .frame(width: 240, height: 56)
                .rotationEffect(.degrees(-16))
                .offset(x: drift ? 110 : -110)
                .blur(radius: 8)
                .blendMode(.plusLighter)

            Circle()
                .fill(aurora[0].opacity(0.4))
                .frame(width: 150, height: 150)
                .blur(radius: 36)
                .offset(x: drift ? 28 : -22, y: pulse ? -16 : 14)
                .blendMode(.plusLighter)

            Circle()
                .fill(aurora[3].opacity(0.32))
                .frame(width: 120, height: 120)
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
