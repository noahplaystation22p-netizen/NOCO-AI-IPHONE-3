import ActivityKit
import SwiftUI
import WidgetKit

@main
struct NOCOAISpeakWidgetBundle: WidgetBundle {
    var body: some Widget {
        SpeakLiveActivityWidget()
        ImageLiveActivityWidget()
        AgentLiveActivityWidget()
        NOCOQuickActionsWidget()
    }
}

// MARK: - Speak Live Activity

struct SpeakLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SpeakActivityAttributes.self) { context in
            SpeakLockScreenView(state: context.state, label: context.attributes.sessionLabel)
                .activityBackgroundTint(Color.black.opacity(0.42))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "nocoai://speak"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SpeakExpandedAuraCore(state: context.state)
                        .frame(width: 44, height: 44)
                        .padding(.leading, 2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SpeakIslandLiveBadge(state: context.state)
                        .padding(.trailing, 2)
                }
                DynamicIslandExpandedRegion(.center) {
                    SpeakIslandExpandedHeader(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SpeakIslandExpandedGlassPanel(state: context.state)
                        .padding(.horizontal, 2)
                        .padding(.bottom, 2)
                }
            } compactLeading: {
                // Brighter rainbow, still clipped inside the pill.
                SpeakRainbowCore(state: context.state, diameter: 12, showSymbol: true, compact: true)
                    .frame(width: 18, height: 18)
                    .padding(.leading, 4)
                    .padding(.trailing, 1)
            } compactTrailing: {
                SpeakMiniVisualizer(
                    bars: Array(context.state.bars.prefix(5)),
                    level: context.state.level,
                    barWidth: 2.2,
                    spacing: 1.6,
                    phaseRaw: context.state.phaseRaw
                )
                .frame(width: 34, height: 14)
                .padding(.trailing, 3)
            } minimal: {
                SpeakRainbowCore(state: context.state, diameter: 11, showSymbol: false, compact: true)
            }
            .widgetURL(URL(string: "nocoai://speak"))
            .keylineTint(SpeakPhasePalette.accent(for: context.state.phaseRaw).opacity(0.95))
        }
    }
}

enum SpeakPhasePalette {
    static func accent(for phaseRaw: String) -> Color {
        switch phaseRaw {
        case "listening": return .cyan
        case "webSearch": return Color(red: 0.35, green: 0.62, blue: 1)
        case "creatingImage": return Color(red: 0.95, green: 0.45, blue: 0.75)
        case "agentWorking": return .mint
        case "vision": return Color(red: 0.35, green: 0.85, blue: 0.75)
        case "speaking": return Color(red: 0.72, green: 0.55, blue: 1)
        case "error": return .orange
        case "awaitingConfirm": return .yellow
        default: return Color(red: 0.55, green: 0.45, blue: 1)
        }
    }

    static func shortLabel(for phaseRaw: String) -> String {
        switch phaseRaw {
        case "listening": return "Hört zu"
        case "thinking", "processing": return "Denkt"
        case "webSearch": return "Web"
        case "creatingImage": return "Bild"
        case "agentWorking": return "Agent"
        case "vision": return "Vision"
        case "speaking": return "Spricht"
        case "awaitingConfirm": return "OK?"
        case "error": return "Fehler"
        case "idle": return "Bereit"
        default: return "Voice"
        }
    }

    /// Island-safe status line — never truncated mid-word.
    static func statusHeadline(for state: SpeakActivityAttributes.ContentState) -> String {
        if state.isMuted, state.phaseRaw != "speaking" {
            return "Pausiert"
        }
        let t = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        switch state.phaseRaw {
        case "listening": return "Voice AI hört zu"
        case "thinking", "processing": return "Voice AI denkt"
        case "speaking": return "Voice AI spricht"
        case "webSearch": return "Websuche läuft"
        case "creatingImage": return "NOCO erstellt Bild"
        case "agentWorking": return "NOCO arbeitet"
        case "vision": return "NOCO sieht"
        case "awaitingConfirm": return "Bestätigung nötig"
        case "error": return "Fehler"
        case "idle": return "Voice AI bereit"
        default: return "NOCO Voice AI"
        }
    }

    static func statusDetail(for state: SpeakActivityAttributes.ContentState) -> String {
        if state.isMuted, state.phaseRaw != "speaking" {
            return "Mikrofon aus — Mute lösen zum Sprechen"
        }
        let d = state.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !d.isEmpty { return d }
        switch state.phaseRaw {
        case "listening": return "Rede natürlich — Pause sendet"
        case "thinking", "processing": return "Einen Moment…"
        case "speaking": return "Antwort wird vorgelesen"
        case "webSearch": return "Live Knowledge aktiv"
        default: return "NOCO Voice AI"
        }
    }

    static func gradientColors(for phaseRaw: String, muted: Bool) -> [Color] {
        if muted { return [.orange, .yellow, .orange] }
        switch phaseRaw {
        case "webSearch":
            return [
                Color(red: 0.25, green: 0.55, blue: 1),
                Color(red: 0.45, green: 0.75, blue: 1),
                Color(red: 0.55, green: 0.4, blue: 1),
                Color(red: 0.25, green: 0.55, blue: 1)
            ]
        case "creatingImage":
            return [
                Color(red: 0.95, green: 0.4, blue: 0.7),
                Color(red: 1, green: 0.65, blue: 0.45),
                Color(red: 0.7, green: 0.4, blue: 1),
                Color(red: 0.95, green: 0.4, blue: 0.7)
            ]
        case "agentWorking":
            return [.mint, .cyan, Color(red: 0.4, green: 0.9, blue: 0.7), .mint]
        case "listening":
            return [.cyan, .purple, .mint, .cyan]
        case "speaking":
            return [
                Color(red: 0.72, green: 0.55, blue: 1),
                Color(red: 0.95, green: 0.45, blue: 0.78),
                Color(red: 0.35, green: 0.85, blue: 1),
                Color(red: 0.72, green: 0.55, blue: 1)
            ]
        case "thinking", "processing":
            return [
                Color(red: 0.55, green: 0.4, blue: 1),
                Color(red: 0.35, green: 0.85, blue: 1),
                Color(red: 0.95, green: 0.45, blue: 0.78),
                Color(red: 0.55, green: 0.4, blue: 1)
            ]
        default:
            return [
                Color(red: 0.35, green: 0.85, blue: 1),
                Color(red: 0.65, green: 0.45, blue: 1),
                Color(red: 0.95, green: 0.45, blue: 0.75),
                Color(red: 0.4, green: 0.95, blue: 0.75),
                Color(red: 0.35, green: 0.85, blue: 1)
            ]
        }
    }

    static func symbol(for phaseRaw: String, muted: Bool) -> String {
        if muted { return "mic.slash.fill" }
        switch phaseRaw {
        case "listening": return "mic.fill"
        case "processing", "thinking": return "sparkles"
        case "webSearch": return "globe"
        case "creatingImage": return "paintbrush.pointed.fill"
        case "agentWorking": return "cpu.fill"
        case "vision": return "eye.fill"
        case "awaitingConfirm": return "questionmark.circle.fill"
        case "speaking": return "speaker.wave.3.fill"
        case "error": return "exclamationmark.circle"
        default: return "mic.fill"
        }
    }

    /// Animation speed factor — higher = faster spin (thinking/web). Soft morphing, not frantic.
    static func spinPeriod(for phaseRaw: String) -> Double {
        switch phaseRaw {
        case "listening": return 7.2
        case "thinking", "processing": return 4.2
        case "webSearch": return 3.6
        case "speaking": return 5.0
        case "creatingImage", "agentWorking", "vision": return 4.8
        default: return 7.5
        }
    }
}

/// Expanded Island: larger core with soft rainbow aura (stays inside Island bounds).
struct SpeakExpandedAuraCore: View {
    let state: SpeakActivityAttributes.ContentState

    var body: some View {
        let period = SpeakPhasePalette.spinPeriod(for: state.phaseRaw)
        TimelineView(.animation(minimumInterval: 0.12, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let spin = (t.truncatingRemainder(dividingBy: period) / period) * 360
            let pulse: Double = {
                switch state.phaseRaw {
                case "listening": return 0.96 + 0.04 * abs(sin(t * 1.2))
                case "thinking", "processing", "webSearch": return 0.93 + 0.07 * abs(sin(t * 2.4))
                case "speaking": return 0.94 + 0.06 * abs(sin(t * 2.0 + Double(state.level) * 2.5))
                default: return 0.96 + 0.04 * abs(sin(t * 1.0))
                }
            }()
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: SpeakPhasePalette.gradientColors(for: state.phaseRaw, muted: state.isMuted)
                                .map { $0.opacity(0.88) },
                            center: .center,
                            angle: .degrees(spin)
                        )
                    )
                    .frame(width: 52, height: 52)
                    .blur(radius: 9)
                    .opacity(1.0)
                    .scaleEffect(pulse)
                    .blendMode(.plusLighter)

                Circle()
                    .fill(
                        AngularGradient(
                            colors: SpeakPhasePalette.gradientColors(for: state.phaseRaw, muted: state.isMuted),
                            center: .center,
                            angle: .degrees(spin * 1.35)
                        )
                    )
                    .frame(width: 40, height: 40)
                    .blur(radius: 4)
                    .opacity(0.75)
                    .scaleEffect(pulse)
                    .blendMode(.plusLighter)

                Circle()
                    .fill(
                        AngularGradient(
                            colors: SpeakPhasePalette.gradientColors(for: state.phaseRaw, muted: state.isMuted),
                            center: .center,
                            angle: .degrees(-spin * 0.6)
                        )
                    )
                    .frame(width: 34, height: 34)
                    .blur(radius: 3.5)
                    .opacity(0.7)

                SpeakRainbowCore(state: state, diameter: 26)
            }
            .frame(width: 44, height: 44)
            .compositingGroup()
        }
    }
}

struct SpeakIslandLiveBadge: View {
    let state: SpeakActivityAttributes.ContentState

    private var badge: (String, Color) {
        if state.isMuted { return ("PAUSE", .orange) }
        if state.phaseRaw == "error" { return ("ERR", .orange) }
        // Live Activity exists ⇒ Voice session is active. Never show a false "OFF".
        return ("LIVE", .green)
    }

    var body: some View {
        let (label, color) = badge
        VStack(alignment: .trailing, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                        )
                )
            Text(SpeakPhasePalette.shortLabel(for: state.phaseRaw))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
        }
    }
}

struct SpeakIslandExpandedHeader: View {
    let state: SpeakActivityAttributes.ContentState

    var body: some View {
        // Title stays stationary — only detail/reply marquees (cheaper for Island).
        VStack(spacing: 3) {
            Text(SpeakPhasePalette.statusHeadline(for: state))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Label {
                Text(SpeakPhasePalette.shortLabel(for: state.phaseRaw))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            } icon: {
                Image(systemName: SpeakPhasePalette.symbol(for: state.phaseRaw, muted: state.isMuted))
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.7))
            .labelStyle(.titleAndIcon)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Liquid-glass style panel for the expanded bottom region.
struct SpeakIslandExpandedGlassPanel: View {
    let state: SpeakActivityAttributes.ContentState

    var body: some View {
        let colors = SpeakPhasePalette.gradientColors(for: state.phaseRaw, muted: state.isMuted)
        TimelineView(.animation(minimumInterval: 0.22, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let drift = (t.truncatingRemainder(dividingBy: 5.5) / 5.5)
            VStack(spacing: 6) {
                SpeakSpeakingDetailText(state: state)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 16, maxHeight: state.phaseRaw == "speaking" ? 52 : 16)

                SpeakIslandWaveform(state: state)
                    .frame(height: 22)

                // Soft moving light edge — kept inside bounds (no heavy outer shadow).
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                colors[0].opacity(0.05),
                                colors[min(1, colors.count - 1)].opacity(0.55),
                                colors[min(2, colors.count - 1)].opacity(0.55),
                                colors[0].opacity(0.05)
                            ],
                            startPoint: UnitPoint(x: drift - 0.3, y: 0.5),
                            endPoint: UnitPoint(x: drift + 0.3, y: 0.5)
                        )
                    )
                    .frame(height: 2)
                    .opacity(0.9)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.14),
                                    Color.white.opacity(0.03),
                                    colors[0].opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: colors.map { $0.opacity(0.55) },
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                }
            }
            .compositingGroup()
            .clipped()
        }
    }
}

/// Expanded Island reply: TTS-synced text with soft marquee when it overflows.
struct SpeakSpeakingDetailText: View {
    let state: SpeakActivityAttributes.ContentState

    var body: some View {
        let text = SpeakPhasePalette.statusDetail(for: state)
        let speaking = state.phaseRaw == "speaking"
        let long = text.count > 36
        SpeakMarqueeText(
            text: text,
            font: .system(size: 11, weight: .medium, design: .rounded),
            foreground: .white.opacity(0.92),
            speed: speaking ? 28 : 24,
            forceScroll: speaking && long,
            lineCount: speaking && text.count > 90 ? 2 : 1
        )
        .animation(.easeInOut(duration: 0.16), value: text)
    }
}

/// Reading-order marquee: start of sentence first, then scroll so later words enter (LTR reading).
struct SpeakMarqueeText: View {
    let text: String
    var font: Font = .caption
    var foreground: Color = .white
    /// Points per second while scrolling.
    var speed: CGFloat = 32
    /// Always scroll while speaking, even if short.
    var forceScroll: Bool = false
    var lineCount: Int = 1

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            TimelineView(.animation(minimumInterval: 0.12, paused: false)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let approxChar: CGFloat = 6.6
                let textWidth = max(CGFloat(text.count) * approxChar, width)
                let overflow = max(0, textWidth - width)
                let needsScroll = forceScroll || overflow > 10
                // Hold the start briefly, then scroll so reading progresses L→R through the sentence.
                let travel = overflow + width * 0.25
                let period = max(Double(travel / max(speed, 8)), 4.0)
                let raw = needsScroll ? t.truncatingRemainder(dividingBy: period) / period : 0
                let progress = needsScroll ? max(0, (raw - 0.12) / 0.76) : 0
                let clamped = min(max(progress, 0), 1)
                // x: 0 → -travel (content moves left; reader advances through text left→right)
                let x = needsScroll ? -clamped * travel : 0

                Text(text)
                    .font(font)
                    .foregroundStyle(foreground)
                    .lineLimit(lineCount)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: x)
                    .frame(width: width, alignment: .leading)
                    .clipped()
                    .mask(
                        LinearGradient(
                            colors: needsScroll
                            ? [.white, .white, .white, .clear]
                            : [.white, .white],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        }
    }
}

/// Living Rainbow AI core for Dynamic Island / Lock Screen (lightweight for WidgetKit).
struct SpeakRainbowCore: View {
    let state: SpeakActivityAttributes.ContentState
    var diameter: CGFloat = 22
    var showSymbol: Bool = true
    /// Compact Island must stay fully inside the pill — no oversized glow.
    var compact: Bool = false

    var body: some View {
        let period = SpeakPhasePalette.spinPeriod(for: state.phaseRaw)
        let interval = max(0.08, min(0.14, period / 42))
        let glowPad: CGFloat = compact ? 3 : (diameter <= 15 ? 3 : 8)
        let outerGlow: CGFloat = compact ? diameter + 4 : diameter + 14
        let midGlow: CGFloat = compact ? diameter + 2 : diameter + 6
        TimelineView(.animation(minimumInterval: interval, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let spin = (t.truncatingRemainder(dividingBy: period) / period) * 360
            let pulse = 0.92 + 0.08 * abs(sin(t * (state.phaseRaw == "listening" ? 2.6 : 3.4)))
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: SpeakPhasePalette.gradientColors(for: state.phaseRaw, muted: state.isMuted),
                            center: .center,
                            angle: .degrees(spin)
                        )
                    )
                    .frame(width: outerGlow, height: outerGlow)
                    .blur(radius: compact ? 1.8 : (diameter > 20 ? 4.2 : 2.6))
                    .opacity(compact ? 0.95 : 0.98)
                    .scaleEffect(pulse)
                    .blendMode(compact ? .normal : .plusLighter)

                Circle()
                    .fill(
                        AngularGradient(
                            colors: SpeakPhasePalette.gradientColors(for: state.phaseRaw, muted: state.isMuted)
                                .map { $0.opacity(0.9) },
                            center: .center,
                            angle: .degrees(spin * 1.2)
                        )
                    )
                    .frame(width: midGlow, height: midGlow)
                    .blur(radius: compact ? 0.9 : (diameter > 20 ? 1.8 : 1.0))
                    .opacity(0.95)
                    .scaleEffect(pulse)

                Circle()
                    .stroke(
                        AngularGradient(
                            colors: SpeakPhasePalette.gradientColors(for: state.phaseRaw, muted: state.isMuted),
                            center: .center,
                            angle: .degrees(-spin * 0.7)
                        ),
                        lineWidth: compact ? 1.25 : max(1.4, diameter * 0.09)
                    )
                    .frame(width: diameter + (compact ? 1 : 3), height: diameter + (compact ? 1 : 3))
                    .opacity(1.0)

                Circle()
                    .fill(Color.black.opacity(0.32))
                    .frame(width: diameter * 0.7, height: diameter * 0.7)

                if showSymbol {
                    Image(systemName: SpeakPhasePalette.symbol(for: state.phaseRaw, muted: state.isMuted))
                        .font(.system(size: max(compact ? 7 : 8, diameter * 0.34), weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: SpeakPhasePalette.gradientColors(for: state.phaseRaw, muted: state.isMuted),
                                center: .center,
                                angle: .degrees(spin * 1.4)
                            )
                        )
                        .frame(width: diameter * 0.36, height: diameter * 0.36)
                }
            }
            .frame(width: diameter + glowPad, height: diameter + glowPad)
            .clipped()
            .compositingGroup()
        }
    }
}

struct SpeakIslandWaveform: View {
    let state: SpeakActivityAttributes.ContentState

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.14, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let colors = SpeakPhasePalette.gradientColors(for: state.phaseRaw, muted: state.isMuted)
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<7, id: \.self) { i in
                    let base = i < state.bars.count ? state.bars[i] : state.level
                    // Always blend a local oscillator so bars never freeze if ActivityKit meters stall.
                    let pulse = 0.14 + 0.22 * abs(sin(t * 5.4 + Double(i) * 0.85))
                    let wave: Double = {
                        switch state.phaseRaw {
                        case "listening":
                            return max(pulse, base * (0.8 + 0.4 * abs(sin(t * 8.2 + Double(i)))))
                        case "speaking":
                            return 0.32 + 0.58 * abs(sin(t * 7.6 + Double(i) * 0.72)) * (0.4 + max(0.18, base))
                        case "webSearch", "thinking", "processing":
                            return 0.22 + 0.55 * abs(sin(t * 4.4 + Double(i) * 0.52))
                        default:
                            return max(pulse, base)
                        }
                    }()
                    Capsule()
                        .fill(LinearGradient(colors: Array(colors.prefix(3)), startPoint: .bottom, endPoint: .top))
                        .frame(width: 4, height: max(5, CGFloat(wave) * 26 + CGFloat(state.level) * 4))
                        .opacity(0.55 + wave * 0.45)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct SpeakLockScreenView: View {
    let state: SpeakActivityAttributes.ContentState
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SpeakExpandedAuraCore(state: state)
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                    Text(SpeakPhasePalette.statusHeadline(for: state))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    SpeakMarqueeText(
                        text: SpeakPhasePalette.statusDetail(for: state),
                        font: .subheadline,
                        foreground: .white.opacity(0.8),
                        speed: state.phaseRaw == "speaking" ? 40 : 28,
                        forceScroll: state.phaseRaw == "speaking"
                    )
                    .frame(height: 18)
                }

                Spacer(minLength: 0)

                SpeakIslandLiveBadge(state: state)
            }

            SpeakIslandWaveform(state: state)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: SpeakPhasePalette.gradientColors(for: state.phaseRaw, muted: state.isMuted)
                                            .map { $0.opacity(0.45) },
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                }
        }
        .padding(16)
    }
}

struct SpeakMiniVisualizer: View {
    var bars: [Double]
    var level: Double
    var barWidth: CGFloat = 4
    var spacing: CGFloat = 3
    var phaseRaw: String = "listening"

    var body: some View {
        let colors = SpeakPhasePalette.gradientColors(for: phaseRaw, muted: false)
        // Local Timeline keeps bars lively even when ActivityKit updates arrive slowly.
        TimelineView(.animation(minimumInterval: 0.07, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<5, id: \.self) { i in
                    let base = i < bars.count ? bars[i] : level
                    let wave: Double = {
                        switch phaseRaw {
                        case "listening":
                            // Always animate locally — never freeze if meter packets stall.
                            let pulse = 0.14 + 0.22 * abs(sin(t * 5.6 + Double(i) * 0.9))
                            return max(pulse, base * (0.85 + 0.35 * abs(sin(t * 8.8 + Double(i)))))
                        case "speaking":
                            return 0.28 + 0.62 * abs(sin(t * 8.4 + Double(i) * 0.75)) * (0.45 + max(0.2, base))
                        case "webSearch", "thinking", "processing":
                            return 0.18 + 0.52 * abs(sin(t * 4.4 + Double(i) * 0.55))
                        default:
                            let pulse = 0.12 + 0.18 * abs(sin(t * 3.8 + Double(i)))
                            return max(pulse, base)
                        }
                    }()
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: Array(colors.prefix(3)),
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: barWidth, height: max(4, min(14, CGFloat(wave) * 16 + CGFloat(level) * 3)))
                        .opacity(0.5 + wave * 0.5)
                }
            }
            .frame(maxHeight: 14, alignment: .center)
            .clipped()
        }
    }
}

// MARK: - Image Live Activity

struct ImageLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ImageActivityAttributes.self) { context in
            ImageLockScreenView(state: context.state, prompt: context.attributes.prompt)
                .activityBackgroundTint(Color.black.opacity(0.4))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "nocoai://images"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "photo.artframe")
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.percentLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text(context.state.status)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(context.state.insight)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.progress)
                        .tint(.orange)
                        .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "photo.artframe")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                Text(context.state.percentLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
            } minimal: {
                Image(systemName: "photo.fill")
                    .foregroundStyle(.orange)
            }
            .widgetURL(URL(string: "nocoai://images"))
        }
    }
}

struct ImageLockScreenView: View {
    let state: ImageActivityAttributes.ContentState
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: state.isDone ? "checkmark.circle.fill" : "photo.artframe")
                    .font(.title2)
                    .foregroundStyle(state.isDone ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.status)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(prompt)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(state.etaLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            ProgressView(value: state.progress)
                .tint(.orange)
            Text(state.insight)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(2)
        }
        .padding(16)
    }
}

// MARK: - Agent Live Activity

struct AgentLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgentActivityAttributes.self) { context in
            AgentLockScreenView(state: context.state, goal: context.attributes.goal)
                .activityBackgroundTint(Color.black.opacity(0.45))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "nocoai://agent"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "cpu.fill")
                        .foregroundStyle(.mint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.percentLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text(context.state.status)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(context.state.insight)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.progress)
                        .tint(.mint)
                        .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "cpu.fill")
                    .foregroundStyle(.mint)
            } compactTrailing: {
                Text(context.state.percentLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.mint)
            } minimal: {
                Image(systemName: "cpu")
                    .foregroundStyle(.mint)
            }
            .widgetURL(URL(string: "nocoai://agent"))
        }
    }
}

struct AgentLockScreenView: View {
    let state: AgentActivityAttributes.ContentState
    let goal: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: state.isDone ? "checkmark.circle.fill" : "cpu.fill")
                    .font(.title2)
                    .foregroundStyle(state.isDone ? Color.green : Color.mint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.status)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(goal)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(state.percentLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            ProgressView(value: state.progress)
                .tint(.mint)
            Text(state.insight)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(2)
        }
        .padding(16)
    }
}

// MARK: - Home Screen Quick Actions Widget

struct NOCOQuickActionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> NOCOQuickActionsEntry {
        NOCOQuickActionsEntry(date: .now, statusLine: "NOCO AI")
    }

    func getSnapshot(in context: Context, completion: @escaping (NOCOQuickActionsEntry) -> Void) {
        completion(NOCOQuickActionsEntry(date: .now, statusLine: loadStatusLine()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NOCOQuickActionsEntry>) -> Void) {
        let entry = NOCOQuickActionsEntry(date: .now, statusLine: loadStatusLine())
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadStatusLine() -> String {
        let suite = UserDefaults(suiteName: "group.de.noco.nocoai")
        if suite?.bool(forKey: "nocoai.widget.online") == true {
            return "PC online"
        }
        if let host = suite?.string(forKey: "nocoai.host"), !host.isEmpty {
            return "NOCO · \(host)"
        }
        return "NOCO AI"
    }
}

struct NOCOQuickActionsEntry: TimelineEntry {
    let date: Date
    let statusLine: String
}

struct NOCOQuickActionsWidget: Widget {
    let kind = "NOCOQuickActionsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NOCOQuickActionsProvider()) { entry in
            NOCOQuickActionsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("NOCO Schnellaktionen")
        .description("Voice AI, Bildideen und Agent direkt öffnen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NOCOQuickActionsWidgetView: View {
    var entry: NOCOQuickActionsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.cyan)
                Text(entry.statusLine)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            if family == .systemSmall {
                Link(destination: URL(string: "nocoai://speak")!) {
                    label("Voice", systemImage: "waveform")
                }
                Link(destination: URL(string: "nocoai://images")!) {
                    label("Bilder", systemImage: "paintbrush.pointed")
                }
            } else {
                HStack(spacing: 8) {
                    Link(destination: URL(string: "nocoai://speak")!) {
                        label("Voice", systemImage: "waveform")
                    }
                    Link(destination: URL(string: "nocoai://images")!) {
                        label("Bilder", systemImage: "paintbrush.pointed")
                    }
                    Link(destination: URL(string: "nocoai://agent")!) {
                        label("Agent", systemImage: "cpu")
                    }
                }
            }
        }
        .padding(12)
    }

    private func label(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        )
        .foregroundStyle(.primary)
    }
}
