import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    metricsRow
                    usageCharts
                    systemCards
                }
                .padding(20)
            }
            .nocoBackground()
            .navigationTitle("Dashboard")
            .refreshable { await connection.refreshStatus(showLoading: true) }
        }
    }

    private var metricsRow: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            statCard(title: "Anfragen", value: "\(connection.status.requestCount ?? 0)", icon: "bubble.left.and.bubble.right")
            statCard(title: "Tokens", value: formatCount(connection.status.tokenCount), icon: "textformat.123")
            statCard(title: "Antwortzeit", value: responseText, icon: "bolt.fill")
            statCard(title: "Laufzeit", value: uptimeText, icon: "clock.fill")
        }
    }

    private var usageCharts: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Auslastung").font(.headline)
                gaugeRow(title: "GPU", value: connection.status.gpuPercent, color: NOCOAITheme.accent)
                gaugeRow(title: "CPU", value: connection.status.cpuPercent, color: NOCOAITheme.accentSecondary)
                gaugeRow(title: "RAM", value: ramPercent, color: NOCOAITheme.success)
            }
        }
    }

    private var systemCards: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("PC-Status").font(.headline)
                HStack {
                    StatusBadge(online: connection.isOnline, label: connection.isOnline ? "Online" : "Offline")
                    Spacer()
                    if let model = connection.status.model {
                        Text(model).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let features = connection.features, !features.enabled.isEmpty {
                    Text("Features: \(features.enabled.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(NOCOAITheme.secondaryText(for: scheme))
                }
            }
        }
    }

    private func statCard(title: String, value: String, icon: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NOCOAITheme.secondaryText(for: scheme))
                Text(value)
                    .font(.title2.bold())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func gaugeRow(title: String, value: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(value.map { String(format: "%.0f %%", $0) } ?? "—")
                    .font(.subheadline.monospacedDigit())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: geo.size.width * CGFloat((value ?? 0) / 100))
                }
            }
            .frame(height: 8)
        }
    }

    private var ramPercent: Double? {
        guard let used = connection.status.ramUsedGB, let total = connection.status.ramTotalGB, total > 0 else { return nil }
        return used / total * 100
    }

    private var responseText: String {
        guard let ms = connection.status.responseTimeMs else { return "—" }
        return ms >= 1000 ? String(format: "%.1f s", ms / 1000) : String(format: "%.0f ms", ms)
    }

    private var uptimeText: String {
        guard let s = connection.status.uptimeSeconds else { return "—" }
        let h = Int(s) / 3600
        let m = (Int(s) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m) min"
    }

    private func formatCount(_ n: Int?) -> String {
        guard let n else { return "—" }
        if n >= 1000 { return String(format: "%.1fk", Double(n) / 1000) }
        return "\(n)"
    }
}
