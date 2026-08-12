import SwiftUI

struct WatchLastAnswerView: View {
    @EnvironmentObject private var controller: WatchController

    private var answer: String {
        controller.snapshot.lastAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                WatchSectionHeader(title: "Last Answer", phase: .idle)

                if answer.isEmpty {
                    Text("Noch keine Antwort.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(answer)
                        .font(.body)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 4)
        }
        .onAppear {
            // Prefer the latest complete snapshot answer.
            controller.session.refreshStatus()
        }
    }
}
