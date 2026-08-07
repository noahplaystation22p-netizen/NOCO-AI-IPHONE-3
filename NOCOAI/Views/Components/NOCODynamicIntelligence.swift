import SwiftUI

// MARK: - Rainbow Intelligence Palette

/// Shared rainbow light language for NOCO Dynamic Intelligence.
enum NOCORainbow {
    static let blue = Color(red: 0.32, green: 0.72, blue: 1.0)
    static let violet = Color(red: 0.58, green: 0.42, blue: 1.0)
    static let pink = Color(red: 0.95, green: 0.42, blue: 0.78)
    static let green = Color(red: 0.35, green: 0.92, blue: 0.62)
    static let teal = Color(red: 0.28, green: 0.88, blue: 0.86)

    static var flow: [Color] {
        [blue, violet, pink, teal, green, blue]
    }

    static var softFlow: [Color] {
        flow.map { $0.opacity(0.85) }
    }

    static func angular(spinning: Bool = false) -> AngularGradient {
        AngularGradient(
            colors: flow,
            center: .center,
            angle: .degrees(spinning ? 360 : 0)
        )
    }
}

/// Visual energy state for the living KI core.
enum NOCOIntelligenceEnergy: Equatable {
    case idle
    case listening
    case thinking
    case speaking
    case working
    case success
    case vision

    var intensity: Double {
        switch self {
        case .idle: return 0.35
        case .listening: return 0.7
        case .thinking: return 0.75
        case .speaking: return 0.9
        case .working: return 0.85
        case .success: return 0.65
        case .vision: return 0.8
        }
    }

    var spinSeconds: Double {
        switch self {
        case .idle: return 18
        case .listening: return 10
        case .thinking: return 7
        case .speaking: return 5.5
        case .working: return 6
        case .success: return 12
        case .vision: return 8
        }
    }
}

enum NOCOIntelligenceCoreSize {
    case compact   // chat bubble / status
    case medium    // cards / agent
    case hero      // Speak / image theater

    var diameter: CGFloat {
        switch self {
        case .compact: return 36
        case .medium: return 72
        case .hero: return 168
        }
    }

    var glow: CGFloat {
        switch self {
        case .compact: return 10
        case .medium: return 18
        case .hero: return 42
        }
    }
}

// MARK: - Living KI Core

/// Central NOCO Dynamic Intelligence effect — reusable rainbow glass KI core.
struct NOCOIntelligenceCore: View {
    var energy: NOCOIntelligenceEnergy = .idle
    var size: NOCOIntelligenceCoreSize = .medium
    var level: CGFloat = 0
    var progress: Double? = nil
    var systemImage: String? = nil
    var label: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    @State private var breathe = false

    private var d: CGFloat { size.diameter }
    private var activeIntensity: Double {
        energy.intensity + Double(min(max(level, 0), 1)) * 0.25
    }

    private var allowMotion: Bool {
        !reduceMotion
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
            && ProcessInfo.processInfo.thermalState != .serious
            && ProcessInfo.processInfo.thermalState != .critical
    }

    var body: some View {
        ZStack {
            // Outer soft rainbow bloom
            Circle()
                .fill(
                    AngularGradient(colors: NOCORainbow.softFlow, center: .center)
                )
                .frame(width: d * 1.55, height: d * 1.55)
                .blur(radius: size.glow)
                .opacity(0.28 + activeIntensity * 0.35)
                .scaleEffect(breathe ? 1.08 : 0.94)
                .rotationEffect(.degrees(spin ? 360 : 0))

            // Mid glass halo
            Circle()
                .stroke(
                    AngularGradient(colors: NOCORainbow.flow, center: .center),
                    lineWidth: size == .compact ? 1.2 : 1.8
                )
                .frame(width: d * 1.18, height: d * 1.18)
                .blur(radius: 0.4)
                .opacity(0.55 + activeIntensity * 0.3)
                .rotationEffect(.degrees(spin ? -360 : 0))
                .scaleEffect(1 + level * 0.08)

            // Core glass disc
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: d, height: d)
                .overlay(
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.35),
                                    NOCORainbow.violet.opacity(0.12),
                                    .clear
                                ],
                                center: .topLeading,
                                startRadius: 2,
                                endRadius: d * 0.7
                            )
                        )
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.55),
                                    NOCORainbow.blue.opacity(0.25),
                                    NOCORainbow.pink.opacity(0.35)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: NOCORainbow.violet.opacity(0.25 + activeIntensity * 0.2), radius: size.glow * 0.45)

            if let progress {
                Circle()
                    .trim(from: 0, to: max(0.04, min(progress, 1)))
                    .stroke(
                        AngularGradient(colors: NOCORainbow.flow, center: .center),
                        style: StrokeStyle(lineWidth: size == .hero ? 5 : 3, lineCap: .round)
                    )
                    .frame(width: d * 0.92, height: d * 0.92)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.45), value: progress)
            }

            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: d * 0.28, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [NOCORainbow.blue, NOCORainbow.violet, NOCORainbow.pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(
                        .pulse,
                        options: .repeating,
                        isActive: allowMotion && energy != .idle && energy != .success
                    )
            } else if size != .compact {
                // Organic inner light
                Circle()
                    .fill(
                        AngularGradient(colors: NOCORainbow.flow.map { $0.opacity(0.85) }, center: .center)
                    )
                    .frame(width: d * 0.28, height: d * 0.28)
                    .blur(radius: 2)
                    .opacity(0.9)
                    .scaleEffect(breathe ? 1.15 : 0.9)
            }

            if let label, size == .hero {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .offset(y: d * 0.72)
            }
        }
        .frame(width: d * 1.7, height: d * 1.7)
        .allowsHitTesting(false)
        .onAppear { startMotion() }
        .onChange(of: energy) { _, _ in startMotion() }
        .accessibilityHidden(true)
    }

    private func startMotion() {
        guard allowMotion else {
            spin = false
            breathe = false
            return
        }
        withAnimation(.linear(duration: energy.spinSeconds).repeatForever(autoreverses: false)) {
            spin = true
        }
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
            breathe = true
        }
    }
}

// MARK: - Flowing rainbow light strip / scan

struct NOCORainbowFlowLine: View {
    var height: CGFloat = 2
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shift = false

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: NOCORainbow.flow,
                    startPoint: shift ? .leading : .trailing,
                    endPoint: shift ? .trailing : .leading
                )
            )
            .frame(height: height)
            .opacity(0.75)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 3.8).repeatForever(autoreverses: true)) {
                    shift = true
                }
            }
    }
}

struct NOCOVisionScanBeam: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var y: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [
                    .clear,
                    NOCORainbow.blue.opacity(0.55),
                    NOCORainbow.violet.opacity(0.35),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 3)
            .blur(radius: 1)
            .offset(y: reduceMotion ? geo.size.height * 0.4 : y)
            .onAppear {
                guard !reduceMotion else { return }
                y = 8
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    y = max(16, geo.size.height - 16)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Thinking chip (chat)

/// In-chat living status — never floats above the composer.
struct NOCOThinkingChip: View {
    var mode: AIMode = .auto
    var phase: ModeWorkPhase = .understanding
    var isFile: Bool = false
    var statusOverride: String? = nil

    @State private var startedAt = Date()
    @State private var elapsed: TimeInterval = 0

    private var line: (emoji: String, text: String) {
        if let override = statusOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            let emoji = override.contains("Verbindung") ? "📡" : "…"
            return (emoji, override)
        }
        return NOCOChatStatusCopy.line(mode: mode, phase: phase, isFile: isFile)
    }

    private var energy: NOCOIntelligenceEnergy {
        switch phase {
        case .idle: return .idle
        case .understanding: return .thinking
        case .analyzing: return .thinking
        case .executing: return mode.isAgentPower ? .working : .speaking
        case .done: return .success
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            NOCOIntelligenceCore(energy: energy, size: .compact, systemImage: nil)
                .frame(width: 40, height: 40)
                .overlay {
                    Text(line.emoji)
                        .font(.system(size: 14))
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(line.emoji)  \(line.text)")
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.32), value: phase)
                    .animation(.easeInOut(duration: 0.32), value: mode)
                NOCORainbowFlowLine(height: 2)
                    .frame(maxWidth: 160)
                Text(elapsedLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: 220, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            AngularGradient(colors: NOCORainbow.flow.map { $0.opacity(0.45) }, center: .center),
                            lineWidth: 1
                        )
                )
                .shadow(color: NOCORainbow.violet.opacity(0.18), radius: 14, y: 4)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 900_000_000)
                elapsed = Date().timeIntervalSince(startedAt)
            }
        }
    }

    private var elapsedLabel: String {
        let s = Int(elapsed)
        if s < 60 { return "\(s)s" }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Mode-aware German status lines for the living chat indicator.
enum NOCOChatStatusCopy {
    static func line(mode: AIMode, phase: ModeWorkPhase, isFile: Bool = false) -> (emoji: String, text: String) {
        if phase == .done {
            return ("✅", mode.isAgentPower ? "Aufgabe abgeschlossen." : "Fertig.")
        }

        if isFile {
            switch phase {
            case .understanding: return ("📄", "Liest Datei…")
            case .analyzing: return ("📄", "Verarbeitet Datei…")
            case .executing: return ("⚙️", "Erstellt Antwort…")
            default: return ("📄", "Verarbeitet Datei…")
            }
        }

        switch mode {
        case .agent:
            switch phase {
            case .understanding: return ("🧠", "Agent analysiert Aufgabe…")
            case .analyzing: return ("📋", "Erstellt Plan…")
            case .executing: return ("⚙️", "Führt Aktionen aus…")
            default: return ("🧠", "Agent arbeitet…")
            }
        case .image:
            switch phase {
            case .understanding: return ("🎨", "Versteht Bildidee…")
            case .analyzing: return ("✨", "Formuliert Prompt…")
            case .executing: return ("🎨", "Erstellt Bild…")
            default: return ("🎨", "Erstellt Bild…")
            }
        case .vision:
            switch phase {
            case .understanding: return ("👁", "Schaut sich das Bild an…")
            case .analyzing, .executing: return ("👁", "Analysiert Bild…")
            default: return ("👁", "Analysiert Bild…")
            }
        case .writing:
            switch phase {
            case .understanding: return ("✍️", "Liest Auftrag…")
            case .analyzing: return ("✍️", "Plant Text…")
            case .executing: return ("✍️", "Schreibt…")
            default: return ("✍️", "Schreibt…")
            }
        case .developer:
            switch phase {
            case .understanding: return ("💻", "Liest Code-Kontext…")
            case .analyzing: return ("💻", "Analysiert…")
            case .executing: return ("⚙️", "Erstellt Lösung…")
            default: return ("💻", "Arbeitet am Code…")
            }
        case .study:
            switch phase {
            case .understanding: return ("📚", "Versteht Thema…")
            case .analyzing: return ("🧠", "Denkt nach…")
            case .executing: return ("✨", "Erklärt…")
            default: return ("📚", "Lernt mit dir…")
            }
        case .creative:
            switch phase {
            case .understanding: return ("✨", "Sammelt Impulse…")
            case .analyzing: return ("🎨", "Entwickelt Ideen…")
            case .executing: return ("✨", "Formuliert Konzept…")
            default: return ("✨", "Kreativ am Werk…")
            }
        default:
            switch phase {
            case .understanding: return ("🧠", "Versteht deine Anfrage…")
            case .analyzing: return ("✨", "Denkt über die beste Lösung nach…")
            case .executing: return ("⚙️", "Erstellt Antwort…")
            default: return ("🧠", "Verarbeitet Anfrage…")
            }
        }
    }
}

// MARK: - Premium press / glass helpers

struct NOCOGlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 22
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmer = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(scheme == .dark ? 0.08 : 0.4),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                AngularGradient(
                                    colors: NOCORainbow.flow.map {
                                        $0.opacity(scheme == .dark ? (shimmer ? 0.4 : 0.22) : (shimmer ? 0.32 : 0.16))
                                    },
                                    center: .center
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: NOCORainbow.blue.opacity(0.12), radius: 16, y: 6)
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 5.2).repeatForever(autoreverses: true)) {
                    shimmer = true
                }
            }
    }
}

extension View {
    func nocoGlass(cornerRadius: CGFloat = 22) -> some View {
        modifier(NOCOGlassSurface(cornerRadius: cornerRadius))
    }
}
