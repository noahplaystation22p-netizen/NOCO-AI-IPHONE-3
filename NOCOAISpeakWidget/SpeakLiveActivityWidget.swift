import ActivityKit
import SwiftUI
import WidgetKit

@main
struct NOCOAISpeakWidgetBundle: WidgetBundle {
    var body: some Widget {
        SpeakLiveActivityWidget()
        ImageLiveActivityWidget()
    }
}

struct SpeakLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SpeakActivityAttributes.self) { context in
            // Lock Screen + banner (not just Dynamic Island)
            SpeakLockScreenView(state: context.state, label: context.attributes.sessionLabel)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: islandIcon(context.state))
                        .foregroundStyle(context.state.isMuted ? .orange : .cyan)
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
                        Text(context.state.detail)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(2)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SpeakMiniVisualizer(bars: context.state.bars, level: context.state.level)
                        .frame(height: 32)
                        .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: islandIcon(context.state))
                    .foregroundStyle(context.state.isMuted ? .orange : .cyan)
            } compactTrailing: {
                SpeakMiniVisualizer(bars: Array(context.state.bars.prefix(5)), level: context.state.level, barWidth: 2.5, spacing: 2)
                    .frame(width: 36, height: 16)
            } minimal: {
                Image(systemName: context.state.isMuted ? "mic.slash.fill" : "waveform")
                    .foregroundStyle(context.state.isMuted ? .orange : .cyan)
            }
            .widgetURL(URL(string: "nocoai://speak"))
        }
    }

    private func islandIcon(_ state: SpeakActivityAttributes.ContentState) -> String {
        if state.isMuted { return "mic.slash.fill" }
        switch state.phaseRaw {
        case "listening": return "ear.fill"
        case "processing": return "sparkles"
        case "speaking": return "speaker.wave.3.fill"
        case "error": return "exclamationmark.circle"
        default: return "mic.fill"
        }
    }
}

struct SpeakLockScreenView: View {
    let state: SpeakActivityAttributes.ContentState
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: state.isMuted
                                    ? [.orange, .yellow, .orange]
                                    : [.cyan, .purple, .mint, .cyan],
                                center: .center
                            )
                        )
                        .frame(width: 48, height: 48)
                        .opacity(0.9)
                    Image(systemName: state.isMuted ? "mic.slash.fill" : "waveform.circle.fill")
                        .foregroundStyle(.white)
                        .font(.system(size: 20, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                    Text(state.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
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

            SpeakMiniVisualizer(bars: state.bars, level: state.level, barWidth: 7, spacing: 5)
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
                    .frame(width: barWidth, height: max(6, CGFloat(value) * 38 + CGFloat(level) * 6))
                    .opacity(0.55 + value * 0.45)
            }
        }
        .animation(.easeOut(duration: 0.12), value: bars)
    }
}

struct ImageLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ImageActivityAttributes.self) { context in
            ImageLockScreenView(state: context.state, prompt: context.attributes.prompt)
                .activityBackgroundTint(Color.black.opacity(0.4))
                .activitySystemActionForegroundColor(.white)
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
