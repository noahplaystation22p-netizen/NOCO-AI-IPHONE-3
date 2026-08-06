import SwiftUI

/// Premium real-time camera vision — NOCO with eyes.
struct VisionLiveView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @StateObject private var session = VisionLiveSessionController()
    @State private var showConsent = false
    @State private var appear = false
    @State private var pulseLive = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if session.isLive {
                VisionLiveCameraPreview(session: session.camera.session)
                    .ignoresSafeArea()
                    .opacity(appear ? 1 : 0)
            } else {
                IntelligenceAtmosphere()
                    .ignoresSafeArea()
            }

            // Phase wash
            RadialGradient(
                colors: [
                    session.phase.color.opacity(session.isAnalyzing ? 0.35 : 0.12),
                    .clear
                ],
                center: .center,
                startRadius: 40,
                endRadius: 420
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.45), value: session.phase)

            VStack(spacing: 0) {
                topChrome
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                if session.isLive {
                    livePill
                        .padding(.top, 8)
                }

                LiveScreenIntelligenceWave(phase: session.phase)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                Spacer(minLength: 0)

                bottomStack
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            session.bind { connection.companionAPI() }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) { appear = true }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulseLive = true }
            if !session.hasConsent { showConsent = true }
        }
        .onDisappear { session.stopLive() }
        .sheet(isPresented: $showConsent) { consentSheet }
        .alert("Vision Live", isPresented: Binding(
            get: { session.lastError != nil },
            set: { if !$0 { session.clearError() } }
        )) {
            Button("OK", role: .cancel) { session.clearError() }
        } message: {
            Text(session.lastError ?? "")
        }
    }

    private var topChrome: some View {
        HStack(spacing: 10) {
            Button {
                session.stopLive()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("NOCO Vision Live")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(session.phase.title) · \(session.statusLine)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            if session.isLive {
                Button {
                    Task { await session.camera.flipCamera() }
                } label: {
                    Image(systemName: "camera.rotate.fill")
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }

            Button {
                HapticService.open()
                if session.isLive {
                    session.stopLive()
                } else if session.hasConsent {
                    Task { await session.startLive() }
                } else {
                    showConsent = true
                }
            } label: {
                Text(session.isLive ? "Stop" : "Start")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        (session.isLive ? Color.red.opacity(0.9) : session.intent.accent).gradient,
                        in: Capsule()
                    )
            }
        }
    }

    private var livePill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .scaleEffect(pulseLive ? 1.2 : 0.85)
            Text("LIVE · Kamera aktiv")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
            if !session.activeModelLabel.isEmpty {
                Text("· \(session.activeModelLabel)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var bottomStack: some View {
        VStack(spacing: 10) {
            if !session.suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(session.suggestions) { s in
                            Button {
                                HapticService.selection()
                                Task { await session.captureAndAsk(s.prompt) }
                            } label: {
                                Label(s.title, systemImage: s.systemImage)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            .disabled(!session.isLive || session.isAnalyzing)
                        }
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(VisionLiveIntent.allCases) { intent in
                        Button {
                            HapticService.selection()
                            session.intent = intent
                        } label: {
                            Text(intent.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(session.intent == intent ? .white : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background {
                                    if session.intent == intent {
                                        Capsule().fill(intent.accent.gradient)
                                    } else {
                                        Capsule().fill(.ultraThinMaterial)
                                    }
                                }
                        }
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LiveScreenQuality.allCases) { q in
                        Button {
                            session.quality = q
                            HapticService.selection()
                        } label: {
                            Text(q.title)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background {
                                    if session.quality == q {
                                        Capsule().fill(session.phase.color.opacity(0.85))
                                    } else {
                                        Capsule().fill(.ultraThinMaterial)
                                    }
                                }
                                .foregroundStyle(session.quality == q ? .white : .primary)
                        }
                    }
                }
            }

            if let last = session.turns.last(where: { $0.role == .assistant }) {
                Text(last.text)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .lineLimit(8)
            }

            HStack(spacing: 10) {
                TextField("Frag NOCO…", text: $session.draft)
                    .focused($inputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button {
                    Task { await session.startVoiceAsk() }
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .disabled(!session.isLive)

                Button {
                    let q = session.draft
                    session.draft = ""
                    inputFocused = false
                    Task { await session.captureAndAsk(q.isEmpty ? nil : q) }
                } label: {
                    Image(systemName: session.isAnalyzing ? "hourglass" : "sparkles")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(session.intent.accent.gradient, in: Circle())
                }
                .disabled(!session.isLive || session.isAnalyzing || !connection.isOnline)
            }

            HStack {
                Toggle("Auto-Assistent", isOn: $session.autoAssist)
                    .labelsHidden()
                Text("Auto-Assistent")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text("Live Screen-kompatibel")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        }
    }

    private var consentSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "eye.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(session.intent.accent)
                Text("Kamera mit Zustimmung")
                    .font(.title2.bold())
                Text("NOCO Vision Live nutzt die Kamera nur, wenn du startest. Es gibt keine heimliche Aufnahme. Frames bleiben im Speicher und werden zur Analyse an deinen NOCO Companion gesendet. Lokale OCR läuft auf dem Gerät.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Label("Klare LIVE-Anzeige", systemImage: "checkmark.seal.fill")
                    Label("Jederzeit stoppen", systemImage: "checkmark.seal.fill")
                    Label("Modell-Profile & Datenschutz", systemImage: "checkmark.seal.fill")
                }
                .font(.subheadline)
                .foregroundStyle(NOCOAITheme.success)
                Spacer()
                Button {
                    session.grantConsent()
                    showConsent = false
                    Task { await session.startLive() }
                } label: {
                    Text("Zustimmen & Kamera starten")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(session.intent.accent.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.white)
                }
                Button("Ablehnen") {
                    showConsent = false
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.secondary)
            }
            .padding(24)
            .navigationTitle("Datenschutz")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
