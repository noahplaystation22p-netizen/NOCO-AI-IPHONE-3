import SwiftUI

struct WritingToolsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let sourceText: String
    var onPick: (WritingTool) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Schreibwerkzeuge")
                        .font(.title2.weight(.bold))
                    Text(sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          ? "Tippe zuerst Text in den Chat — oder wähle ein Werkzeug für den letzten Text."
                          : "Sinn bleibt erhalten. Die Arbeit läuft über deinen Companion.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(WritingTool.allCases) { tool in
                            Button {
                                HapticService.selection()
                                onPick(tool)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Image(systemName: tool.systemImage)
                                        .font(.title3)
                                        .foregroundStyle(NOCOAITheme.accent)
                                    Text(tool.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(tool.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .stroke(NOCOAITheme.glowPrimary.opacity(0.25), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(IntelligencePressStyle(haptic: { HapticService.soft() }))
                        }
                    }
                }
                .padding(20)
            }
            .nocoBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct IntelligenceIdeaChips: View {
    var onSelect: (IntelligenceIdea) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ideen")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(IntelligenceIdea.allCases) { idea in
                        Button {
                            HapticService.light()
                            onSelect(idea)
                        } label: {
                            Text(idea.title)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct ReplyActionBar: View {
    let replyText: String
    var onAction: (ReplyAction) -> Void

    var body: some View {
        EmptyView()
    }
}
