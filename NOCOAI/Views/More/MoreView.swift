import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            List {
                Section("Tools") {
                    NavigationLink {
                        ImagesHubView()
                            .environmentObject(connection)
                    } label: {
                        Label("Bilder", systemImage: "photo.artframe")
                    }
                    NavigationLink {
                        CodeStudioView()
                            .environmentObject(connection)
                    } label: {
                        Label("Code Studio", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    NavigationLink {
                        SettingsView()
                            .environmentObject(connection)
                    } label: {
                        Label("Einstellungen", systemImage: "gearshape.fill")
                    }
                }

                if let features = connection.features, !features.enabled.isEmpty {
                    Section("PC-Features") {
                        ForEach(features.enabled, id: \.self) { feature in
                            Label(feature, systemImage: icon(for: feature))
                        }
                    }
                }

                Section("Verbindung") {
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
                    Text("NOCO AI Companion v2.5")
                    Text("Apple Intelligence Icon · Cloud-Chat · Text auf dem PC.")
                        .font(.footnote)
                        .foregroundStyle(NOCOAITheme.secondaryText(for: scheme))
                }
            }
            .navigationTitle("Mehr")
        }
    }

    private func icon(for feature: String) -> String {
        switch feature.lowercased() {
        case "chat": return "bubble.left.and.bubble.right"
        case "bilder": return "photo.artframe"
        case "code": return "chevron.left.forwardslash.chevron.right"
        case "vision": return "eye"
        case "sync": return "arrow.triangle.2.circlepath"
        default: return "checkmark.circle"
        }
    }
}
