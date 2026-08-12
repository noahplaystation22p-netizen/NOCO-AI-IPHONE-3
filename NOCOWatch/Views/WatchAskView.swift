import SwiftUI

struct WatchAskView: View {
    @EnvironmentObject private var controller: WatchController
    @FocusState private var focused: Bool

    private var phase: WatchStatusSnapshot.Phase {
        controller.localPhase != .idle ? controller.localPhase : controller.snapshot.phase
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                WatchSectionHeader(title: "Ask NOCO", phase: phase)

                if !controller.snapshot.isOnline && !controller.session.phoneReachable {
                    WatchOfflineBanner(message: "NOCO Offline")
                }

                TextField("Ask NOCO", text: $controller.askText, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($focused)
                    .textInputAutocapitalization(.sentences)

                if phase == .thinking || phase == .connecting {
                    Text("Thinking…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let err = controller.errorLine {
                    Text(err)
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
                .disabled(controller.askText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || phase == .thinking)
            }
            .padding(.horizontal, 4)
        }
    }
}

struct WatchOfflineBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(.red).frame(width: 7, height: 7)
            Text(message)
                .font(.caption2.weight(.semibold))
        }
        .padding(.vertical, 4)
    }
}
