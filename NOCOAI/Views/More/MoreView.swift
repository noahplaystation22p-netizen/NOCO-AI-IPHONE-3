import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ImagesHubView()
                            .environmentObject(connection)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Bildideen")
                                Text("Bilder erzeugen & verbessern")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "paintbrush.pointed.fill")
                                .foregroundStyle(NOCOAITheme.accent)
                        }
                    }

                    NavigationLink {
                        CodeStudioView()
                            .environmentObject(connection)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Code Assist")
                                Text("Code erklären, fixen, verbessern")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .foregroundStyle(NOCOAITheme.accent)
                        }
                    }

                    NavigationLink {
                        SettingsView()
                            .environmentObject(connection)
                    } label: {
                        Label("Einstellungen", systemImage: "gearshape.fill")
                    }
                } header: {
                    Text("Intelligence")
                } footer: {
                    Text("Funktionen laufen auf deinem Windows-PC — das iPhone steuert nur.")
                }

                if let features = connection.features, !features.enabled.isEmpty {
                    Section("PC-Fähigkeiten") {
                        ForEach(features.enabled, id: \.self) { feature in
                            Label(friendlyFeature(feature), systemImage: icon(for: feature))
                        }
                    }
                }

                Section("Intelligence Sync") {
                    LabeledContent("PC", value: connection.serverHost)
                    LabeledContent("Status", value: connection.isOnline ? "Online" : "Offline")
                    SyncBadge(active: connection.chat.isSyncActive)
                }

                Section {
                    Button("Verbindung trennen", role: .destructive) {
                        connection.disconnect()
                        HapticService.medium()
                    }
                }

                Section("Info") {
                    Text("NOCO AI Companion v2.9")
                    Text("Speak · Schreibwerkzeuge · Bildideen · Intelligence Sync")
                        .font(.footnote)
                        .foregroundStyle(NOCOAITheme.secondaryText(for: scheme))
                }
            }
            .navigationTitle("Studio")
        }
    }

    private func friendlyFeature(_ feature: String) -> String {
        switch feature.lowercased() {
        case "chat": return "Chat"
        case "bilder", "images": return "Bildideen"
        case "code": return "Code Assist"
        case "vision": return "Visuelle Intelligenz"
        case "sync": return "Intelligence Sync"
        case "browser", "browser_agent": return "Browser-Agent (PC)"
        default: return feature
        }
    }

    private func icon(for feature: String) -> String {
        switch feature.lowercased() {
        case "chat": return "bubble.left.and.bubble.right"
        case "bilder", "images": return "paintbrush.pointed"
        case "code": return "chevron.left.forwardslash.chevron.right"
        case "vision": return "eye"
        case "sync": return "arrow.triangle.2.circlepath"
        default: return "sparkles"
        }
    }
}
