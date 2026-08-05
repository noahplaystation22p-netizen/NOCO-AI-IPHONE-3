import SwiftUI

/// Studio hub — Speak, System & Settings; Code Assist in Settings.
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
                        subtitle: "Speak, System & Sync — alles an einem Ort.",
                        online: connection.isOnline
                    )
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 12)

                    IntelligenceWaveRibbon()
                        .frame(height: 28)
                        .padding(.horizontal, 8)
                        .opacity(0.85)

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
                            HomeView()
                                .environmentObject(connection)
                        } label: {
                            IntelligenceFeatureTile(
                                title: "System",
                                subtitle: "GPU · CPU · RAM · Latenz",
                                systemImage: "desktopcomputer",
                                accent: NOCOAITheme.glowSecondary
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            SettingsView()
                                .environmentObject(connection)
                        } label: {
                            IntelligenceFeatureTile(
                                title: "Einstellungen",
                                subtitle: "Sync, Speak, Stimme",
                                systemImage: "gearshape.fill",
                                accent: NOCOAITheme.glowAccent
                            )
                        }
                        .buttonStyle(.plain)

                        IntelligenceFeatureTile(
                            title: "NOCO Sync",
                            subtitle: connection.isOnline ? "Live mit dem PC" : "Warte auf PC…",
                            systemImage: "arrow.triangle.2.circlepath",
                            accent: NOCOAITheme.glowPrimary
                        )
                    }
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 18)

                    connectionCard
                        .opacity(appear ? 1 : 0)

                    Text("NOCO AI Companion v4.6")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .nocoBackground()
            .overlay {
                FloatingIntelligenceDots(count: 2)
                    .opacity(0.35)
                    .opacity(0.22)
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
                    Text("NOCO Sync")
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

                Button {
                    Task { await connection.refreshStatus(showLoading: true) }
                    HapticService.light()
                } label: {
                    Label("Verbindung prüfen", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
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
        case "code": return "Code"
        case "vision": return "Vision"
        case "sync": return "Sync"
        case "typing": return "Tipp-Sync"
        default: return feature
        }
    }
}
