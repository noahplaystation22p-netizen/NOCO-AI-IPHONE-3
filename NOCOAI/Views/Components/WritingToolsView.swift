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
                    Text("Wie Apple Writing Tools — die Arbeit passiert auf deinem PC.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    IntelligenceShimmerLine()
                        .padding(.vertical, 4)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(WritingTool.allCases) { tool in
                            Button {
                                HapticService.selection()
                                onPick(tool)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    Image(systemName: tool.systemImage)
                                        .font(.title3)
                                        .foregroundStyle(NOCOAITheme.accent)
                                    Text(tool.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
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
                            .buttonStyle(.plain)
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
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            Capsule()
                                                .stroke(
                                                    LinearGradient(
                                                        colors: [
                                                            NOCOAITheme.glowPrimary.opacity(0.55),
                                                            NOCOAITheme.glowSecondary.opacity(0.35)
                                                        ],
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    ),
                                                    lineWidth: 1
                                                )
                                        )
                                        .shadow(color: NOCOAITheme.glowPrimary.opacity(0.2), radius: 8)
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(NOCOAITheme.accent)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
}

struct ReplyActionBar: View {
    let replyText: String
    var onAction: (ReplyAction) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ReplyAction.allCases) { action in
                    Button {
                        HapticService.selection()
                        onAction(action)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}
