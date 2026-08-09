import SwiftUI

struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            compactChrome
            if model.showToolsPanel {
                toolsBar
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                    ))
            }
            if model.showAskPanel {
                askPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if !model.isConfigured || !model.hasFullAccess {
                accessHint
            }
            KeyboardLayoutView(model: model)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 2)
        }
        .padding(.top, 4)
        .background(keyboardBackground)
        .overlay {
            if model.isProcessing || model.showIntelligenceBurst || model.isAsking || model.isDictationPolishing {
                IntelligenceRewriteOverlay(
                    phase: model.animationPhase,
                    title: model.overlayTitle
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.96)),
                    removal: .opacity
                ))
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: model.isProcessing)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: model.showIntelligenceBurst)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: model.showAskPanel)
        .animation(.spring(response: 0.38, dampingFraction: 0.84), value: model.showToolsPanel)
        .animation(.easeInOut(duration: 0.18), value: model.animationPhase)
        .animation(.easeInOut(duration: 0.12), value: model.isDictating)
    }

    // MARK: - Compact chrome (Apple-height friendly)

    private var compactChrome: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                Color(red: 0.45, green: 0.78, blue: 1.0),
                                Color(red: 0.72, green: 0.55, blue: 1.0),
                                Color(red: 1.0, green: 0.55, blue: 0.72),
                                Color(red: 0.45, green: 0.92, blue: 0.78),
                                Color(red: 0.45, green: 0.78, blue: 1.0)
                            ],
                            center: .center
                        )
                    )
                    .frame(width: 16, height: 16)
                    .blur(radius: 0.3)
                Image(systemName: "sparkles")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.leading, 2)

            Button {
                model.openNOCOAI()
            } label: {
                HStack(spacing: 5) {
                    Text("NOCO AI")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    if model.showAskPanel {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .opacity(0.75)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: model.showAskPanel
                                ? [
                                    Color(red: 0.55, green: 0.45, blue: 1.0),
                                    Color(red: 0.35, green: 0.75, blue: 1.0),
                                    Color(red: 0.45, green: 0.95, blue: 0.8)
                                ]
                                : [
                                    Color(red: 0.38, green: 0.55, blue: 1.0),
                                    Color(red: 0.55, green: 0.45, blue: 0.98)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .foregroundStyle(.white)
                .shadow(color: Color(red: 0.45, green: 0.55, blue: 1).opacity(0.35), radius: 6, y: 1)
            }
            .buttonStyle(SoftPressStyle())
            .accessibilityLabel("NOCO AI Fragefeld")

            Button {
                model.toggleAITools()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 10, weight: .bold))
                    Text("AI Tools")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    if model.showToolsPanel {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .opacity(0.75)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            model.showToolsPanel
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.45, blue: 0.65),
                                        Color(red: 0.55, green: 0.45, blue: 1.0),
                                        Color(red: 0.35, green: 0.85, blue: 1.0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            : AnyShapeStyle(Color.white.opacity(0.12))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(model.showToolsPanel ? 0.28 : 0.14), lineWidth: 0.6)
                        )
                )
                .foregroundStyle(.white.opacity(0.95))
            }
            .buttonStyle(SoftPressStyle())
            .accessibilityLabel("AI Tools")

            Spacer(minLength: 4)

            if model.isProcessing && !model.isDictating {
                Text(model.isDictationPolishing ? "formt…" : "arbeitet…")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    // MARK: - AI Tools bar (does not capture typing)

    private var toolsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(model.quickAIActions.enumerated()), id: \.element.rawValue) { index, action in
                    Button {
                        model.runBuiltinAction(action)
                    } label: {
                        if action == .improve {
                            PremiumImproveChip(active: model.showToolsPanel)
                        } else {
                            HStack(spacing: 5) {
                                Image(systemName: action.systemImage)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(action.title)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .foregroundStyle(.white.opacity(0.92))
                            .background {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.1))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .buttonStyle(SoftPressStyle())
                    .disabled(model.isProcessing)
                    .opacity(model.isProcessing ? 0.45 : 1)
                    .offset(y: model.showToolsPanel ? 0 : 8)
                    .animation(
                        .spring(response: 0.42, dampingFraction: 0.78).delay(Double(index) * 0.04),
                        value: model.showToolsPanel
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Ask panel (text field only)

    private var askPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                HStack(alignment: .center, spacing: 2) {
                    if model.askDraft.isEmpty {
                        // Cursor at the start of the field (not after the placeholder).
                        BlinkingCursor()
                        Text("Frag NOCO AI…")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.38))
                    } else {
                        Text(model.askDraft)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                        BlinkingCursor()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    AngularGradient(
                                        colors: [
                                            Color(red: 0.45, green: 0.8, blue: 1),
                                            Color(red: 0.7, green: 0.5, blue: 1),
                                            Color(red: 1.0, green: 0.55, blue: 0.75),
                                            Color(red: 0.45, green: 0.95, blue: 0.75),
                                            Color(red: 0.45, green: 0.8, blue: 1)
                                        ],
                                        center: .center
                                    ),
                                    lineWidth: model.showAskPanel ? 1.4 : 1
                                )
                        )
                )

                Button {
                    model.sendAsk()
                } label: {
                    Image(systemName: model.isAsking ? "ellipsis" : "arrow.up.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .symbolEffect(.pulse, options: .repeating, isActive: model.isAsking)
                        .foregroundStyle(
                            model.askDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.white.opacity(0.3)
                            : Color(red: 0.55, green: 0.75, blue: 1)
                        )
                }
                .disabled(
                    model.isAsking ||
                    model.askDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            if !model.askReply.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView {
                        Text(model.askReply)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.95))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 44, maxHeight: 110)

                    HStack(spacing: 10) {
                        Button("Einfügen") {
                            model.insertAskReply()
                        }
                        .font(.caption.weight(.bold))
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.42, green: 0.55, blue: 1))
                        .controlSize(.mini)

                        Button("Neue Frage") {
                            model.clearAskDraft()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))

                        Button("Schließen") {
                            model.closeNOCOAI()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.5, green: 0.8, blue: 1).opacity(0.45),
                                            Color(red: 0.7, green: 0.5, blue: 1).opacity(0.35)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    private var accessHint: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.orange)
                .frame(width: 5, height: 5)
            Text(model.statusLine)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
            Spacer(minLength: 0)
            if !model.isConfigured {
                Button("App") {
                    model.openAppForSync()
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.4, green: 0.55, blue: 1))
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var keyboardBackground: some View {
        ZStack {
            // Apple-like dark keyboard chrome with soft AI wash
            Color(red: 0.11, green: 0.11, blue: 0.12)

            LinearGradient(
                colors: [
                    Color(red: 0.35, green: 0.45, blue: 0.95).opacity(0.14),
                    Color(red: 0.55, green: 0.35, blue: 0.9).opacity(0.08),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Blinking caret (Ask-field focus cue)

private struct BlinkingCursor: View {
    @State private var on = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(Color(red: 0.55, green: 0.78, blue: 1.0))
            .frame(width: 2, height: 16)
            .opacity(on ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    on = false
                }
            }
    }
}

// MARK: - Apple Intelligence–style aurora overlay

private struct IntelligenceRewriteOverlay: View {
    var phase: KeyboardViewModel.AnimationPhase
    var title: String

    @State private var spin = false
    @State private var pulse = false
    @State private var drift = false
    @State private var startedAt = Date()
    @State private var elapsed: TimeInterval = 0

    private let rainbow: [Color] = [
        Color(red: 0.98, green: 0.42, blue: 0.55),
        Color(red: 1.0, green: 0.72, blue: 0.35),
        Color(red: 0.55, green: 0.92, blue: 0.55),
        Color(red: 0.4, green: 0.78, blue: 1.0),
        Color(red: 0.62, green: 0.48, blue: 1.0),
        Color(red: 0.95, green: 0.45, blue: 0.78),
        Color(red: 0.98, green: 0.42, blue: 0.55)
    ]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.28))

            AngularGradient(colors: rainbow, center: .center)
                .blur(radius: 36)
                .opacity(pulse ? 0.72 : 0.38)
                .scaleEffect(pulse ? 1.2 : 0.9)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .blendMode(.plusLighter)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.65), rainbow[3].opacity(0.5), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 260, height: 52)
                .rotationEffect(.degrees(-18))
                .offset(x: drift ? 120 : -120)
                .blur(radius: 7)
                .blendMode(.plusLighter)

            Circle()
                .fill(rainbow[4].opacity(0.45))
                .frame(width: 140, height: 140)
                .blur(radius: 32)
                .offset(x: drift ? 30 : -24, y: pulse ? -18 : 12)
                .blendMode(.plusLighter)

            Circle()
                .fill(rainbow[1].opacity(0.35))
                .frame(width: 110, height: 110)
                .blur(radius: 28)
                .offset(x: drift ? -28 : 22, y: pulse ? 16 : -10)
                .blendMode(.plusLighter)

            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(AngularGradient(colors: rainbow, center: .center), lineWidth: 2.6)
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(spin ? 360 : 0))

                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 32, height: 32)

                    Image(systemName: phase == .success
                          ? "checkmark"
                          : (phase == .writing ? "wand.and.stars" : "sparkles"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: phase)
                        .symbolEffect(.pulse, options: .repeating, value: phase == .thinking || phase == .writing)
                }

                if phase == .thinking || phase == .writing {
                    Text(phase == .writing ? "Schreibt…" : (title.isEmpty ? "Denkt…" : title))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                    Text(elapsedLabel)
                        .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.65))
                } else if phase == .success {
                    Text("Fertig")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.94))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.55),
                                        rainbow[3].opacity(0.5),
                                        rainbow[4].opacity(0.45)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
        }
        .allowsHitTesting(false)
        .onAppear {
            startedAt = Date()
            withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.easeInOut(duration: 1.55).repeatForever(autoreverses: true)) { drift = true }
        }
        .onChange(of: phase) { _, new in
            if new == .thinking { startedAt = Date(); elapsed = 0 }
        }
        .task(id: phase) {
            guard phase == .thinking || phase == .writing else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                elapsed = Date().timeIntervalSince(startedAt)
            }
        }
    }

    private var elapsedLabel: String {
        let s = Int(elapsed)
        return s < 60 ? "\(s)s" : String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct SoftPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// Hero chip for „Verbessern“ — Apple Intelligence–style rainbow glow (main AI Tools action).
private struct PremiumImproveChip: View {
    var active: Bool

    private let rainbow: [Color] = [
        Color(red: 1.0, green: 0.42, blue: 0.58),
        Color(red: 1.0, green: 0.72, blue: 0.32),
        Color(red: 0.45, green: 0.95, blue: 0.6),
        Color(red: 0.4, green: 0.78, blue: 1.0),
        Color(red: 0.72, green: 0.48, blue: 1.0),
        Color(red: 1.0, green: 0.42, blue: 0.58)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let spin = (t.truncatingRemainder(dividingBy: 3.6) / 3.6) * 360
            let pulse = 0.94 + 0.06 * abs(sin(t * 2.0))
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 12, weight: .bold))
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: active)
                Text("Verbessern")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(.white)
            .background {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.45, green: 0.4, blue: 0.95).opacity(0.55),
                                    Color(red: 0.35, green: 0.7, blue: 1.0).opacity(0.45)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Capsule(style: .continuous)
                        .stroke(
                            AngularGradient(colors: rainbow, center: .center, angle: .degrees(spin)),
                            lineWidth: 1.8
                        )
                    Capsule(style: .continuous)
                        .stroke(
                            AngularGradient(
                                colors: rainbow.map { $0.opacity(0.85) },
                                center: .center,
                                angle: .degrees(-spin * 0.8)
                            ),
                            lineWidth: 1.0
                        )
                }
            }
            .shadow(color: Color(red: 0.55, green: 0.45, blue: 1).opacity(0.5 * pulse), radius: 8, y: 1)
            .scaleEffect(pulse)
        }
        .accessibilityLabel("Verbessern")
    }
}
