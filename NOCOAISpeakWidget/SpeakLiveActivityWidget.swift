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
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "nocoai://speak"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SpeakIslandGlyph(state: context.state, size: 22)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.isMuted ? "Mute" : (context.state.isOnline ? "Live" : "Offline"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(context.state.isMuted ? .orange : (context.state.isOnline ? .green : .red))
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text(context.state.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.75)
                            .lineLimit(1)
                        Text(context.state.detail)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(2)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SpeakMiniVisualizer(bars: context.state.bars, level: context.state.level, phaseRaw: context.state.phaseRaw)
                        .frame(height: 34)
                        .padding(.top, 4)
                }
            } compactLeading: {
                SpeakIslandGlyph(state: context.state, size: 14)
            } compactTrailing: {
                SpeakMiniVisualizer(
                    bars: Array(context.state.bars.prefix(5)),
                    level: context.state.level,
                    barWidth: 2.5,
                    spacing: 2,
                    phaseRaw: context.state.phaseRaw
                )
                .frame(width: 36, height: 16)
            } minimal: {
                Image(systemName: context.state.isMuted ? "mic.slash.fill" : islandMinimalIcon(context.state))
                    .foregroundStyle(context.state.isMuted ? .orange : SpeakPhasePalette.accent(for: context.state.phaseRaw))
            }
            .widgetURL(URL(string: "nocoai://speak"))
        }
    }

    private func islandMinimalIcon(_ state: SpeakActivityAttributes.ContentState) -> String {
        SpeakPhasePalette.symbol(for: state.phaseRaw, muted: false)
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
        case "listening": return "ear.fill"
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
}

struct SpeakIslandGlyph: View {
    let state: SpeakActivityAttributes.ContentState
    var size: CGFloat = 18

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: false)) { timeline in
            let spin = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 4) / 4
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: SpeakPhasePalette.gradientColors(for: state.phaseRaw, muted: state.isMuted),
                            center: .center,
                            angle: .degrees(spin * 360)
                        )
                    )
                    .frame(width: size + 10, height: size + 10)
                    .opacity(0.85)
                    .blur(radius: 0.4)
                Image(systemName: SpeakPhasePalette.symbol(for: state.phaseRaw, muted: state.isMuted))
                    .font(.system(size: size * 0.72, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}

struct SpeakLockScreenView: View {
    let state: SpeakActivityAttributes.ContentState
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TimelineView(.animation(minimumInterval: 0.1, paused: false)) { timeline in
                    let spin = timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 5) / 5
                    ZStack {
                        Circle()
                            .fill(
                                AngularGradient(
                                    colors: SpeakPhasePalette.gradientColors(for: state.phaseRaw, muted: state.isMuted),
                                    center: .center,
                                    angle: .degrees(spin * 360)
                                )
                            )
                            .frame(width: 52, height: 52)
                            .opacity(0.95)
                            .shadow(color: SpeakPhasePalette.accent(for: state.phaseRaw).opacity(0.45), radius: 8)
                        Image(systemName: SpeakPhasePalette.symbol(for: state.phaseRaw, muted: state.isMuted))
                            .foregroundStyle(.white)
                            .font(.system(size: 20, weight: .semibold))
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                    Text(state.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(state.detail)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(3)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(state.isMuted ? "MUTE" : (state.isOnline ? "LIVE" : "OFF"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(state.isMuted ? .orange : (state.isOnline ? .green : .red))
                    Text("\(Int(state.level * 100))%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            SpeakMiniVisualizer(bars: state.bars, level: state.level, barWidth: 7, spacing: 5, phaseRaw: state.phaseRaw)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .padding(18)
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
        HStack(alignment: .center, spacing: spacing) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, value in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: Array(colors.prefix(3)),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: barWidth, height: max(6, CGFloat(value) * 38 + CGFloat(level) * 6))
                    .opacity(0.55 + value * 0.45)
            }
        }
        .animation(.easeOut(duration: 0.12), value: bars)
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
        .description("Speak, Bildideen und Agent direkt öffnen.")
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
                    label("Speak", systemImage: "waveform")
                }
                Link(destination: URL(string: "nocoai://images")!) {
                    label("Bilder", systemImage: "paintbrush.pointed")
                }
            } else {
                HStack(spacing: 8) {
                    Link(destination: URL(string: "nocoai://speak")!) {
                        label("Speak", systemImage: "waveform")
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
