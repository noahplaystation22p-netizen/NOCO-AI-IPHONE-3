import SwiftUI

struct WatchStatusView: View {
    @EnvironmentObject private var controller: WatchController
    @State private var showDiagnostics = false

    private var snap: WatchStatusSnapshot { controller.snapshot }
    private var watchLink: WatchLinkState { controller.session.watchPhoneLink }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                WatchSectionHeader(
                    title: "Status",
                    phase: softPhase
                )

                linkRow("Watch", watchLink)
                linkRow("NOCO", snap.phoneServerLink)
                linkRow(
                    "Ollama",
                    snap.ollamaReady ? .connected : (snap.phoneServerLink == .connected ? .connecting : .offline),
                    connectedLabel: "Ready"
                )

                statusRow("Pfad", pathLabel)
                statusRow("Modell", snap.modelLabel)
                if let ms = snap.latencyMs {
                    statusRow("Latency", "\(ms) ms")
                }

                if watchLink == .reconnecting || snap.phoneServerLink == .reconnecting {
                    Text(WatchUserFacingError.restoring)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if let err = snap.lastUserError, watchLink != .reconnecting {
                    Text(WatchUserFacingError.sanitize(err))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

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

                Button(showDiagnostics ? "Diagnostics aus" : "Diagnostics") {
                    showDiagnostics.toggle()
                    WatchHaptics.selection()
                }
                .buttonStyle(.bordered)

                if showDiagnostics {
                    diagnosticsBlock
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var softPhase: WatchStatusSnapshot.Phase {
        if watchLink == .reconnecting || snap.phoneServerLink == .reconnecting {
            return .connecting
        }
        if snap.phase == .error { return .idle }
        return snap.phase
    }

    private var pathLabel: String {
        switch snap.connection {
        case .local: return "Local"
        case .remote: return "Remote"
        case .offline: return "—"
        }
    }

    private func linkRow(
        _ title: String,
        _ state: WatchLinkState,
        connectedLabel: String = "Connected"
    ) -> some View {
        HStack {
            Text("\(state.emojiDot) \(title)")
                .font(.caption.weight(.semibold))
            Spacer()
            Text(state == .connected ? connectedLabel : state.label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
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

    private var diagnosticsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NOCO Watch Diagnostics")
                .font(.caption2.weight(.bold))
            statusRow("Watch ↔ iPhone", watchLink.label.uppercased())
            statusRow("iPhone ↔ Server", snap.phoneServerLink.label.uppercased())
            statusRow("Connection", pathLabel.uppercased())
            statusRow("Server", snap.isOnline ? "ONLINE" : "OFFLINE")
            statusRow("Ollama", snap.ollamaReady ? "READY" : "WAIT")
            statusRow("Latency", snap.latencyMs.map { "\($0) ms" } ?? "—")
            statusRow("Last Error", snap.lastTechnicalError ?? snap.lastUserError ?? "None")

            if !controller.session.diagnosticLines.isEmpty {
                Divider().opacity(0.3)
                ForEach(controller.session.diagnosticLines.suffix(8), id: \.self) { line in
                    Text(line)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.top, 4)
    }
}
