import SwiftUI

struct WatchStatusView: View {
    @EnvironmentObject private var controller: WatchController

    private var snap: WatchStatusSnapshot { controller.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                WatchSectionHeader(title: "Status", phase: snap.phase)

                HStack(spacing: 8) {
                    connectionDot
                    Text(connectionLabel)
                        .font(.headline.weight(.semibold))
                }

                statusRow("Modell", snap.modelLabel)
                statusRow("Server", snap.isOnline ? "Erreichbar" : "Offline")
                statusRow("iPhone", snap.phoneReachable ? "Verbunden" : "Nicht erreichbar")
                statusRow("Phase", snap.statusLine)

                if let job = snap.activeJob {
                    Divider().opacity(0.35)
                    Text(job.title)
                        .font(.caption.weight(.bold))
                    if let detail = job.detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: job.progress)
                        .tint(WatchRainbow.blue)
                }

                Button("Aktualisieren") {
                    controller.session.refreshStatus()
                    WatchHaptics.selection()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 4)
        }
    }

    private var connectionDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 10, height: 10)
    }

    private var dotColor: Color {
        switch snap.connection {
        case .local: return .green
        case .remote: return WatchRainbow.blue
        case .offline: return .red
        }
    }

    private var connectionLabel: String {
        switch snap.connection {
        case .local: return "Local"
        case .remote: return "Remote"
        case .offline: return "Offline"
        }
    }

    private func statusRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption2.weight(.medium))
        }
    }
}
