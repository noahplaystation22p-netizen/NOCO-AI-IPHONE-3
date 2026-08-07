import SwiftUI

/// First-run carousel after pairing — shows what NOCO AI can do.
struct OnboardingWelcomeView: View {
    var onFinished: () -> Void

    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Chat mit NOCO",
            subtitle: "Schreibe natürlich — NOCO denkt lokal auf deinem PC und antwortet klar.",
            symbol: "bubble.left.and.bubble.right.fill",
            accent: .chat
        ),
        OnboardingPage(
            title: "Voice AI",
            subtitle: "Sprich mit NOCO über Shortcut oder Dynamic Island — auch unterwegs.",
            symbol: "waveform.circle.fill",
            accent: .voice
        ),
        OnboardingPage(
            title: "Bilder & Vision",
            subtitle: "Ideen erzeugen, Radierer nutzen oder mit der Kamera sehen, was du meinst.",
            symbol: "camera.aperture",
            accent: .vision
        ),
        OnboardingPage(
            title: "Agent & Live Screen",
            subtitle: "Aufgaben am PC erledigen und den Bildschirm verstehen — alles privat bei dir.",
            symbol: "desktopcomputer",
            accent: .agent
        ),
    ]

    var body: some View {
        ZStack {
            IntelligenceAtmosphere()
            FloatingIntelligenceDots(count: 8)
                .opacity(0.45)

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        OnboardingPageView(page: item, active: page == index)
                            .tag(index)
                            .padding(.horizontal, 28)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.45, dampingFraction: 0.86), value: page)

                VStack(spacing: 18) {
                    HStack(spacing: 8) {
                        ForEach(0..<pages.count, id: \.self) { i in
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: i == page
                                            ? NOCORainbow.flow
                                            : [Color.primary.opacity(0.15), Color.primary.opacity(0.15)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: i == page ? 22 : 8, height: 8)
                                .shadow(color: i == page ? NOCORainbow.violet.opacity(0.45) : .clear, radius: 8)
                                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: page)
                        }
                    }

                    Button {
                        HapticService.selection()
                        if page < pages.count - 1 {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                                page += 1
                            }
                        } else {
                            HapticService.success()
                            onFinished()
                        }
                    } label: {
                        Text(page < pages.count - 1 ? "Weiter" : "Los geht’s")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .foregroundStyle(.white)
                            .background {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                NOCORainbow.blue,
                                                NOCORainbow.violet,
                                                NOCORainbow.pink
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: NOCORainbow.violet.opacity(0.4), radius: 18, y: 8)
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 28)

                    if page < pages.count - 1 {
                        Button("Überspringen") {
                            HapticService.soft()
                            onFinished()
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 36)
                .padding(.top, 8)
            }
        }
    }
}

private struct OnboardingPage: Identifiable {
    enum Accent { case chat, voice, vision, agent }
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
    let accent: Accent
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    var active: Bool
    @State private var pulse = false
    @State private var spin = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 40)

            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: NOCORainbow.flow.map { $0.opacity(0.7) },
                            center: .center
                        )
                    )
                    .frame(width: 168, height: 168)
                    .blur(radius: 26)
                    .opacity(pulse ? 0.9 : 0.45)
                    .scaleEffect(pulse ? 1.08 : 0.92)
                    .rotationEffect(.degrees(spin ? 360 : 0))

                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 112, height: 112)
                    .overlay {
                        Circle()
                            .stroke(
                                AngularGradient(colors: NOCORainbow.flow, center: .center),
                                lineWidth: 2.2
                            )
                    }
                    .shadow(color: NOCORainbow.violet.opacity(0.35), radius: 20, y: 6)

                Image(systemName: page.symbol)
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [NOCORainbow.blue, NOCORainbow.violet, NOCORainbow.pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.pulse, options: .repeating, isActive: active)
            }
            .frame(height: 180)

            VStack(spacing: 12) {
                Text(page.title)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(page.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .opacity(active ? 1 : 0.4)
            .offset(y: active ? 0 : 10)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: active)

            Spacer()
        }
        .onAppear { armMotion() }
        .onChange(of: active) { _, on in
            if on { armMotion() }
        }
    }

    private func armMotion() {
        pulse = false
        spin = false
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
            pulse = true
        }
        withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) {
            spin = true
        }
    }
}
