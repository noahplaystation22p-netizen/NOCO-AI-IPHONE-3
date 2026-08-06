import SwiftUI

/// Studio hub — senses first, utilities second. Unified system-AI surface.
struct MoreView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appear = false
    @State private var openLiveScreen = false
    @State private var openAgent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    IntelligenceHeroBanner(
                        title: "NOCO",
                        subtitle: connection.isOnline
                            ? "Dein System-Assistent · \(connection.status.model ?? "lokal")"
                            : "Warte auf Companion…",
                        online: connection.isOnline
                    )
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 12)

                    IntelligenceWaveRibbon()
                        .frame(height: 26)
                        .padding(.horizontal, 8)
                        .opacity(0.85)

                    sectionHeader("Intelligenz", subtitle: "Sprechen, Handeln, Bildschirm")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        Button {
                            HapticService.open()
                            connection.speak.openUI()
                        } label: {
                            IntelligenceFeatureTile(
                                title: "Speak",
                                subtitle: connection.speak.isRunning
                                    ? (connection.speak.visionCameraEnabled ? "Live · Kamera" : "Live aktiv")
                                    : "Sprache · optional Kamera",
                                systemImage: "waveform",
                                accent: Color(red: 0.55, green: 0.45, blue: 1)
                            )
                        }
                        .buttonStyle(IntelligencePressStyle(haptic: { HapticService.soft() }))
                        .disabled(!connection.isOnline && !connection.speak.isRunning)
                        .opacity(connection.isOnline || connection.speak.isRunning ? 1 : 0.55)

                        NavigationLink {
                            AgentDashboardView().environmentObject(connection)
                        } label: {
                            IntelligenceFeatureTile(
                                title: "Agent",
                                subtitle: connection.isOnline ? "Dashboard · Computer" : "Offline",
                                systemImage: "cpu.fill",
                                accent: Color(red: 0.35, green: 0.78, blue: 0.72)
                            )
                        }
                        .buttonStyle(IntelligencePressStyle(haptic: { HapticService.open() }))

                        NavigationLink {
                            LiveScreenView().environmentObject(connection)
                        } label: {
                            IntelligenceFeatureTile(
                                title: "Live Screen",
                                subtitle: "Bildschirmhilfe",
                                systemImage: "rectangle.inset.filled.and.person.filled",
                                accent: Color(red: 0.98, green: 0.55, blue: 0.35)
                            )
                        }
                        .buttonStyle(IntelligencePressStyle(haptic: { HapticService.open() }))

                        NavigationLink {
                            ImagesHubView().environmentObject(connection)
                        } label: {
                            IntelligenceFeatureTile(
                                title: "Bilder",
                                subtitle: "Generieren & Radierer",
                                systemImage: "paintbrush.pointed.fill",
                                accent: Color(red: 0.95, green: 0.55, blue: 0.78)
                            )
                        }
                        .buttonStyle(IntelligencePressStyle(haptic: { HapticService.open() }))
                    }
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 14)

                    sectionHeader("Werkzeuge", subtitle: "System und Einstellungen")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        NavigationLink {
                            HomeView().environmentObject(connection)
                        } label: {
                            IntelligenceFeatureTile(
                                title: "System",
                                subtitle: systemSubtitle,
                                systemImage: "desktopcomputer",
                                accent: NOCOAITheme.glowSecondary
                            )
                        }
                        .buttonStyle(IntelligencePressStyle(haptic: { HapticService.light() }))

                        NavigationLink {
                            SettingsView().environmentObject(connection)
                        } label: {
                            IntelligenceFeatureTile(
                                title: "Einstellungen",
                                subtitle: "Profil · Speak · Tastatur",
                                systemImage: "gearshape.fill",
                                accent: NOCOAITheme.glowAccent
                            )
                        }
                        .buttonStyle(IntelligencePressStyle(haptic: { HapticService.open() }))
                    }
                    .opacity(appear ? 1 : 0)

                    connectionCard
                        .opacity(appear ? 1 : 0)

                    Text(appVersionLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .nocoBackground()
            .overlay {
                if !reduceMotion {
                    FloatingIntelligenceDots(count: 2)
                        .opacity(0.22)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle("Studio")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $openLiveScreen) {
                LiveScreenView().environmentObject(connection)
            }
            .navigationDestination(isPresented: $openAgent) {
                AgentDashboardView().environmentObject(connection)
            }
            .onChange(of: connection.pendingOpenLiveScreen) { _, open in
                if open { openLiveScreen = true; connection.pendingOpenLiveScreen = false }
            }
            .onChange(of: connection.pendingOpenAgent) { _, open in
                if open { openAgent = true; connection.pendingOpenAgent = false }
            }
            .onChange(of: connection.pendingOpenVisionLive) { _, open in
                // Vision gehört in Speak — kein eigener Screen mehr
                if open {
                    connection.pendingOpenVisionLive = false
                    connection.speak.openUI()
                }
            }
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.84)) {
                    appear = true
                }
                consumePendingOpens()
            }
        }
    }

    private var systemSubtitle: String {
        let gpu = connection.status.gpuPercent.map { "\($0)%" } ?? "—"
        return connection.isOnline ? "GPU \(gpu)" : "Offline"
    }

    private var appVersionLabel: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "8.4"
        return "NOCO AI · v\(short)"
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.bold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private func consumePendingOpens() {
        if connection.pendingOpenLiveScreen {
            openLiveScreen = true
            connection.pendingOpenLiveScreen = false
        }
        if connection.pendingOpenAgent {
            openAgent = true
            connection.pendingOpenAgent = false
        }
        if connection.pendingOpenVisionLive {
            connection.pendingOpenVisionLive = false
            connection.speak.openUI()
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
                        Text(connection.serverHost.isEmpty ? "—" : "\(connection.serverHost):\(connection.serverPort)")
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

                if connection.isOnline {
                    Button {
                        Task { await connection.refreshStatus(showLoading: true) }
                        HapticService.light()
                    } label: {
                        Label("Verbindung prüfen", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                } else {
                    Button {
                        Task { await connection.refreshStatus(showLoading: true) }
                        HapticService.open()
                    } label: {
                        Label("Erneut verbinden", systemImage: "link")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
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
        case "bilder", "images": return "Bilder"
        case "code": return "Code"
        case "vision", "visionlive": return "Vision"
        case "agent": return "Agent"
        case "livescreen", "live_screen": return "Live Screen"
        case "sync": return "Sync"
        case "typing": return "Tipp-Sync"
        default: return feature
        }
    }
}
