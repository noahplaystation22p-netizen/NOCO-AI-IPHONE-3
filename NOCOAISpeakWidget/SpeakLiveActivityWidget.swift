import ActivityKit
import SwiftUI
import WidgetKit

@main
struct NOCOAISpeakWidgetBundle: WidgetBundle {
    var body: some Widget {
        SpeakLiveActivityWidget()
    }
}

struct SpeakLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SpeakActivityAttributes.self) { context in
            SpeakLockScreenView(state: context.state, label: context.attributes.sessionLabel)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: islandIcon(context.state.phaseRaw))
                        .foregroundStyle(.cyan)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.isOnline ? "Live" : "Offline")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(context.state.isOnline ? .green : .red)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text(context.state.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(context.state.detail)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SpeakMiniVisualizer(bars: context.state.bars, level: context.state.level)
                        .frame(height: 28)
                        .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: islandIcon(context.state.phaseRaw))
                    .foregroundStyle(.cyan)
            } compactTrailing: {
                SpeakMiniVisualizer(bars: Array(context.state.bars.prefix(5)), level: context.state.level, barWidth: 2.5, spacing: 2)
                    .frame(width: 36, height: 16)
            } minimal: {
                Image(systemName: "waveform")
                    .foregroundStyle(.cyan)
            }
            .widgetURL(URL(string: "nocoai://speak"))
        }
    }

    private func islandIcon(_ phase: String) -> String {
        switch phase {
        case "listening": return "ear.fill"
        case "processing": return "sparkles"
        case "speaking": return "speaker.wave.2.fill"
        case "error": return "exclamationmark.circle"
        default: return "mic.fill"
        }
    }
}

struct SpeakLockScreenView: View {
    let state: SpeakActivityAttributes.ContentState
    let label: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [.cyan, .purple, .mint, .cyan],
                            center: .center
                        )
                    )
                    .frame(width: 42, height: 42)
                    .blur(radius: 0.5)
                    .opacity(0.85)
                Image(systemName: "sparkles")
                    .foregroundStyle(.white)
                    .font(.system(size: 16, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.65))
                Text(state.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(state.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            SpeakMiniVisualizer(bars: state.bars, level: state.level)
                .frame(width: 70, height: 34)
        }
        .padding(16)
    }
}

struct SpeakMiniVisualizer: View {
    var bars: [Double]
    var level: Double
    var barWidth: CGFloat = 4
    var spacing: CGFloat = 3

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(Array(bars.enumerated()), id: \.offset) { index, value in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.cyan,
                                Color.purple,
                                Color.mint
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: barWidth, height: max(4, CGFloat(value) * 30 + CGFloat(level) * 4))
                    .opacity(0.55 + value * 0.45)
            }
        }
        .animation(.easeOut(duration: 0.12), value: bars)
    }
}
