import SwiftUI

struct WatchLastAnswerView: View {
    @EnvironmentObject private var controller: WatchController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                WatchSectionHeader(title: "Last Answer", phase: .idle)

                let answer = controller.snapshot.lastAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
                if answer.isEmpty {
                    Text("Noch keine Antwort.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(answer)
                        .font(.body)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}
