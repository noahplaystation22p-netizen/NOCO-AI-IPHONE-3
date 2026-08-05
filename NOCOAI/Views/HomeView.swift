import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme
    @State private var appear = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                IntelligenceHeroBanner(
                    title: "System",
                    subtitle: connection.serverHost,
                    online: connection.isOnline
                )
                .opacity(appear ? 1 : 0)

                IntelligenceWaveRibbon()
                    .frame(height: 24)
                    .padding(.horizontal, 4)

                ringsRow
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 10)

                smartHints
                    .opacity(appear ? 1 : 0)

                if let activity = connection.status.lastActivity, !activity.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(NOCOAITheme.accent)
                                    .symbolEffect(.pulse, options: .repeating.speed(0.35))
                                Text("Letzte Aktivität").font(.headline)
                            }
                            Text(activity)
                                .font(.subheadline)
                                .foregroundStyle(NOCOAITheme.secondaryText(for: scheme))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let model = connection.status.model, !model.isEmpty {
                    GlassCard {
                        HStack {
                            Label("Modell", systemImage: "brain.head.profile")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(model)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(NOCOAITheme.accent)
                        }
                    }
                }
            }
            .padding(20)
        }
        .nocoBackground()
        .overlay {
            FloatingIntelligenceDots(count: 3)
                .opacity(0.2)
                .allowsHitTesting(false)
        }
        .navigationTitle("System")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await connection.refreshStatus(showLoading: true) }
                } label: {
                    if connection.isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(connection.isRefreshing)
            }
        }
        .refreshable {
            await connection.refreshStatus(showLoading: true)
            await connection.refreshGallery()
        }
        .task {
            await connection.refreshGallery()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) {
                appear = true
            }
        }
    }

    private var ringsRow: some View {
        GlassCard {
            HStack(spacing: 8) {
                IntelligenceProgressRing(
                    progress: (connection.status.gpuPercent ?? 0) / 100,
                    label: "GPU",
                    valueText: percentText(connection.status.gpuPercent),
                    tint: NOCOAITheme.glowPrimary
                )
                .frame(maxWidth: .infinity)
                IntelligenceProgressRing(
                    progress: (connection.status.cpuPercent ?? 0) / 100,
                    label: "CPU",
                    valueText: percentText(connection.status.cpuPercent),
                    tint: NOCOAITheme.glowSecondary
                )
                .frame(maxWidth: .infinity)
                IntelligenceProgressRing(
                    progress: ramProgress,
                    label: "RAM",
                    valueText: ramShort,
                    tint: NOCOAITheme.glowAccent
                )
                .frame(maxWidth: .infinity)
                IntelligenceProgressRing(
                    progress: responseProgress,
                    label: "Latenz",
                    valueText: responseText,
                    tint: Color(red: 0.7, green: 0.45, blue: 1)
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var smartHints: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Einblicke").font(.headline)
                    Spacer()
                    Image(systemName: "sparkles")
                        .foregroundStyle(NOCOAITheme.accent)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                }
                Text(hintText)
                    .font(.subheadline)
                    .foregroundStyle(NOCOAITheme.secondaryText(for: scheme))
                if let features = connection.features, !features.enabled.isEmpty {
                    Text("Aktiv: \(features.enabled.joined(separator: " · "))")
                        .font(.caption)
                        .foregroundStyle(NOCOAITheme.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hintText: String {
        var hints: [String] = []
        if connection.chat.conversations.count > 0 {
            hints.append("\(connection.chat.conversations.count) Chats")
        }
        hints.append("Modus \(connection.chat.mode.label)")
        if !connection.images.gallery.isEmpty {
            hints.append("\(connection.images.gallery.count) Bildideen")
        }
        if let count = connection.status.requestCount, count > 0 {
            hints.append("\(count) Anfragen")
        }
        return hints.isEmpty
            ? "Verbinde dich mit deinem PC und starte im Chat."
            : hints.joined(separator: " · ")
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f%%", value)
    }

    private var ramProgress: Double {
        guard let used = connection.status.ramUsedGB,
              let total = connection.status.ramTotalGB,
              total > 0 else { return 0 }
        return min(used / total, 1)
    }

    private var ramShort: String {
        guard let used = connection.status.ramUsedGB else { return "—" }
        return String(format: "%.0fG", used)
    }

    private var responseProgress: Double {
        guard let ms = connection.status.responseTimeMs else { return 0 }
        return min(ms / 3000, 1)
    }

    private var responseText: String {
        guard let ms = connection.status.responseTimeMs else { return "—" }
        if ms >= 1000 { return String(format: "%.1fs", ms / 1000) }
        return String(format: "%.0fms", ms)
    }
}
