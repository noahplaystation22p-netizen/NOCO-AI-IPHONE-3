import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    statusGrid
                    if let activity = connection.status.lastActivity, !activity.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Letzte Aktivität")
                                    .font(.headline)
                                Text(activity)
                                    .font(.subheadline)
                                    .foregroundStyle(NOCOAITheme.secondaryText(for: scheme))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(20)
            }
            .nocoBackground()
            .navigationTitle("NOCO AI")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await connection.refreshStatus() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(connection.isRefreshing)
                }
            }
            .refreshable {
                await connection.refreshStatus()
            }
        }
    }

    private var header: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(connection.isOnline ? "Online" : "Offline")
                            .font(.title.bold())
                        Text(connection.serverHost)
                            .font(.caption)
                            .foregroundStyle(NOCOAITheme.secondaryText(for: scheme))
                    }
                    Spacer()
                    StatusBadge(
                        online: connection.isOnline,
                        label: connection.isOnline ? "Verbunden" : "Getrennt"
                    )
                }

                if let model = connection.status.model, !model.isEmpty {
                    metricRow(title: "Modell", value: model, icon: "brain.head.profile")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            metricCard(
                title: "GPU",
                value: percentText(connection.status.gpuPercent),
                icon: "gauge.with.needle.fill"
            )
            metricCard(
                title: "CPU",
                value: percentText(connection.status.cpuPercent),
                icon: "cpu"
            )
            metricCard(
                title: "RAM",
                value: ramText,
                icon: "memorychip"
            )
            metricCard(
                title: "Antwortzeit",
                value: responseText,
                icon: "bolt.fill"
            )
        }
    }

    private func metricCard(title: String, value: String, icon: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NOCOAITheme.secondaryText(for: scheme))
                Text(value)
                    .font(.title3.bold())
                    .foregroundStyle(NOCOAITheme.primaryText(for: scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metricRow(title: String, value: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f %%", value)
    }

    private var ramText: String {
        guard let used = connection.status.ramUsedGB else { return "—" }
        if let total = connection.status.ramTotalGB {
            return String(format: "%.1f / %.0f GB", used, total)
        }
        return String(format: "%.1f GB", used)
    }

    private var responseText: String {
        guard let ms = connection.status.responseTimeMs else { return "—" }
        if ms >= 1000 {
            return String(format: "%.1f s", ms / 1000)
        }
        return String(format: "%.0f ms", ms)
    }
}
