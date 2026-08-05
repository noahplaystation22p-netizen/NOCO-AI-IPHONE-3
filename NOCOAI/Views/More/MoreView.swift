import SwiftUI

/// Visual Intelligence hub — clear tiles instead of nested lists.
struct MoreView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme
    @State private var appear = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    IntelligenceHeroBanner(
                        title: "Studio",
                        subtitle: "Speak, Code Assist & Einstellungen — alles auf einen Blick.",
                        online: connection.isOnline
                    )
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 12)

                    IntelligenceShimmerLine()
                        .padding(.horizontal, 24)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        Button {
                            HapticService.medium()
                            connection.speak.openUI()
                        } label: {
                            IntelligenceFeatureTile(
                                title: "Speak",
                                subtitle: connection.speak.isRunning ? "Live aktiv" : "Sprechen & Spoken Reply",
                                systemImage: "waveform",
                                accent: Color(red: 0.55, green: 0.45, blue: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!connection.isOnline && !connection.speak.isRunning)
                        .opacity(connection.isOnline || connection.speak.isRunning ? 1 : 0.55)

                        NavigationLink {
                            CodeStudioView()
                                .environmentObject(connection)
                        } label: {
                            IntelligenceFeatureTile(
                                title: "Code Assist",
                                subtitle: "Erklären, fixen, verbessern",
                                systemImage: "chevron.left.forwardslash.chevron.right",
                                accent: NOCOAITheme.glowPrimary
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            SettingsView()
                                .environmentObject(connection)
                        } label: {
                            IntelligenceFeatureTile(
                                title: "Einstellungen",
                                subtitle: "Sync, Speak-Modell, Stimme",
                                systemImage: "gearshape.fill",
                                accent: NOCOAITheme.glowAccent
                            )
                        }
                        .buttonStyle(.plain)

                        IntelligenceFeatureTile(
                            title: "Tabs",
                            subtitle: "Chat & Bildideen unten in der Leiste",
                            systemImage: "rectangle.split.2x1",
                            accent: NOCOAITheme.glowSecondary
                        )
                    }
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 18)

                    connectionCard
                        .opacity(appear ? 1 : 0)

                    Text("NOCO AI Companion v3.1")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .nocoBackground()
            .overlay {
                FloatingIntelligenceDots(count: 10)
                    .opacity(0.35)
                    .allowsHitTesting(false)
            }
            .navigationTitle("Studio")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) {
                    appear = true
                }
            }
        }
    }

    private var connectionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Intelligence Sync")
                        .font(.headline)
                    Spacer()
                    SyncBadge(active: connection.chat.isSyncActive)
                }
                HStack(spacing: 10) {
                    IntelligencePulseDot(
                        color: connection.isOnline ? NOCOAITheme.success : NOCOAITheme.danger,
                        size: 8
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connection.isOnline ? "PC verbunden" : "PC offline")
                            .font(.subheadline.weight(.semibold))
                        Text(connection.serverHost)
                            .font(.caption)
                            .foregroundStyle(NOCOAITheme.secondaryText(for: scheme))
                    }
                    Spacer()
                    StatusBadge(
                        online: connection.isOnline,
                        label: connection.isOnline ? "Live" : "Offline"
                    )
                }

                if let features = connection.features, !features.enabled.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(features.enabled, id: \.self) { feature in
                                Text(friendlyFeature(feature))
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(NOCOAITheme.accent.opacity(0.12))
                                            .overlay(Capsule().stroke(NOCOAITheme.glowPrimary.opacity(0.3), lineWidth: 1))
                                    )
                                    .foregroundStyle(NOCOAITheme.accent)
                            }
                        }
                    }
                }

                Button(role: .destructive) {
                    connection.disconnect()
                    HapticService.medium()
                } label: {
                    Text("Verbindung trennen")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func friendlyFeature(_ feature: String) -> String {
        switch feature.lowercased() {
        case "chat": return "Chat"
        case "bilder", "images": return "Bildideen"
        case "code": return "Code Assist"
        case "vision": return "Visuelle Intelligenz"
        case "sync": return "Sync"
        default: return feature
        }
    }
}
