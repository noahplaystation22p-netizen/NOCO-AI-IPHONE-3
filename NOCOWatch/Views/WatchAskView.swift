import SwiftUI

struct WatchAskView: View {
    @EnvironmentObject private var controller: WatchController
    @FocusState private var focused: Bool

    private var phase: WatchStatusSnapshot.Phase {
        if controller.localPhase == .thinking { return .thinking }
        if controller.session.watchPhoneLink == .reconnecting { return .connecting }
        return controller.localPhase != .idle ? controller.localPhase : controller.snapshot.phase
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                WatchSectionHeader(title: "Ask NOCO", phase: phase == .error ? .idle : phase)

                connectionBanner

                TextField("Ask NOCO", text: $controller.askText, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($focused)
                    .textInputAutocapitalization(.sentences)

                if phase == .thinking {
                    Text("Thinking…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if phase == .connecting || controller.session.watchPhoneLink == .reconnecting {
                    Text(WatchUserFacingError.restoring)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let err = controller.errorLine {
                    Text(WatchUserFacingError.sanitize(err))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await controller.submitAsk() }
                } label: {
                    Label("Senden", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchRainbow.violet)
                .disabled(
                    controller.askText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || phase == .thinking
                )
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var connectionBanner: some View {
        let link = controller.session.watchPhoneLink
        let server = controller.snapshot.phoneServerLink
        if link == .reconnecting || server == .reconnecting {
            WatchOfflineBanner(message: WatchUserFacingError.restoring, color: .orange)
        } else if link == .offline || server == .offline {
            WatchOfflineBanner(message: WatchUserFacingError.offline, color: .red)
        }
    }
}

struct WatchOfflineBanner: View {
    let message: String
    var color: Color = .red

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(message)
                .font(.caption2.weight(.semibold))
        }
        .padding(.vertical, 4)
    }
}
