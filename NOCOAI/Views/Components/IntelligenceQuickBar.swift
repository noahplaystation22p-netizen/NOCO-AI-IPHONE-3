import SwiftUI

/// Compact system-AI quick launch — connects Chat to Studio senses.
struct IntelligenceQuickBar: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                quickChip(
                    title: connection.speak.isRunning ? "Speak Live" : "Speak",
                    icon: "waveform",
                    accent: Color(red: 0.55, green: 0.45, blue: 1)
                ) {
                    connection.speak.openUI()
                }

                quickChip(title: "Vision", icon: "eye.circle.fill", accent: Color(red: 0.45, green: 0.72, blue: 1.0)) {
                    connection.openStudioFeature(.visionLive)
                }

                quickChip(title: "Agent", icon: "brain.head.profile", accent: Color(red: 0.35, green: 0.78, blue: 0.72)) {
                    connection.openStudioFeature(.agent)
                }

                quickChip(title: "Screen", icon: "rectangle.inset.filled.and.person.filled", accent: Color(red: 0.98, green: 0.55, blue: 0.35)) {
                    connection.openStudioFeature(.liveScreen)
                }

                quickChip(title: "Bilder", icon: "paintbrush.pointed.fill", accent: NOCOAITheme.glowAccent) {
                    connection.pendingTab = 1
                    HapticService.open()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [
                            NOCOAITheme.glowPrimary.opacity(scheme == .dark ? 0.22 : 0.12),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 1)
                }
        }
    }

    private func quickChip(title: String, icon: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button {
            HapticService.selection()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(accent.opacity(scheme == .dark ? 0.18 : 0.12))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [accent.opacity(0.45), accent.opacity(0.12)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(IntelligencePressStyle(haptic: { HapticService.soft() }))
    }
}

enum StudioFeature {
    case visionLive
    case agent
    case liveScreen
}

extension ConnectionStore {
    /// Jump to Studio and open a premium sense feature.
    func openStudioFeature(_ feature: StudioFeature) {
        switch feature {
        case .visionLive:
            speak.openUI()
        case .agent:
            pendingTab = 2
            pendingOpenAgent = true
        case .liveScreen:
            pendingTab = 2
            pendingOpenLiveScreen = true
        }
        HapticService.open()
    }

    /// Prefill Chat input and switch to Chat tab.
    func continueInChat(draft: String) {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            pendingTab = 0
            return
        }
        pendingChatDraft = trimmed
        pendingTab = 0
        HapticService.open()
    }

    /// Seed Agent goal into Chat (Agent works in-chat, not a separate surface).
    func handoffToAgent(goal: String) {
        chat.setMode(.agent)
        pendingChatDraft = String(goal.prefix(500))
        pendingTab = 0
        HapticService.open()
    }

    /// Seed image compose into Chat (stays in chat like Agent — no Bilder tab jump).
    func handoffToImages(prompt: String) {
        chat.setMode(.image)
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            pendingChatDraft = String(trimmed.prefix(400))
            images.prompt = String(trimmed.prefix(400))
        }
        pendingTab = 0
        HapticService.open()
    }
}

/// Contextual starter chips — prompts and feature jumps.
struct IntelligenceSuggestionChips: View {
    @EnvironmentObject private var connection: ConnectionStore

    private struct Chip: Identifiable {
        let id: String
        let title: String
        let run: () -> Void
    }

    private var chips: [Chip] {
        if connection.isOnline {
            return [
                Chip(id: "sum", title: "Zusammenfassen") {
                    Task { await connection.chat.send("Fasse den letzten Kontext klar und kurz zusammen.") }
                },
                Chip(id: "next", title: "Nächste Schritte") {
                    Task { await connection.chat.send("Was wäre jetzt die sinnvollste nächste Aktion?") }
                },
                Chip(id: "speak", title: "Speak") {
                    connection.speak.openUI()
                },
                Chip(id: "agent", title: "Agent starten") {
                    connection.chat.setMode(.agent)
                    HapticService.selection()
                },
                Chip(id: "screen", title: "Live Screen") {
                    connection.openStudioFeature(.liveScreen)
                },
                Chip(id: "plan", title: "Planen") {
                    connection.chat.setMode(.agent)
                    Task { await connection.chat.send("Erstelle einen kurzen, konkreten Plan für mein Ziel.") }
                }
            ]
        }
        return [
            Chip(id: "pair", title: "PC verbinden") {
                connection.pendingTab = 2
                HapticService.open()
            },
            Chip(id: "what", title: "Was kann NOCO?") {
                Task {
                    await connection.chat.send(
                        "Erkläre kurz Speak (mit optionaler Kamera), Agent, Live Screen, Chat und Bilder."
                    )
                }
            }
        ]
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    Button {
                        HapticService.selection()
                        chip.run()
                    } label: {
                        Text(chip.title)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(NOCOAITheme.glowPrimary.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

/// Compact handoff row used by Vision / Live Screen / Agent.
struct IntelligenceHandoffBar: View {
    let text: String
    var onChat: () -> Void
    var onSpeak: (() -> Void)? = nil
    var onAgent: (() -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                handoffChip("Chat", "bubble.left.and.bubble.right.fill", action: onChat)
                if let onSpeak {
                    handoffChip("Vorlesen", "speaker.wave.2.fill", action: onSpeak)
                }
                if let onAgent {
                    handoffChip("Agent", "brain.head.profile", action: onAgent)
                }
            }
        }
    }

    private func handoffChip(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticService.selection()
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
