import SwiftUI

/// Compact NOCO RUNNING plugin inside the main iOS app — talks to Companion :4747.
struct RunningPluginView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme
    @StateObject private var store = RunningPluginStore()
    @State private var question = ""
    @FocusState private var askFocused: Bool

    private let accent = Color(red: 0.32, green: 0.86, blue: 0.58)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusCard
                statsCard
                if !store.weekly.isEmpty {
                    weekCard
                }
                runsCard
                actionsCard
                askCard
                if !store.insights.isEmpty || !store.recommendations.isEmpty {
                    analysisCard
                }
                activityCard
            }
            .padding(20)
        }
        .nocoBackground()
        .navigationTitle("NOCO RUNNING")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            store.bind { connection.companionAPI() }
            Task { await store.refresh() }
        }
        .overlay {
            if store.isBusy {
                ProgressView()
                    .controlSize(.large)
                    .padding(22)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var statusCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Plugin", systemImage: "figure.run")
                        .font(.headline)
                    Spacer()
                    Text(stateLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(stateColor)
                }
                row("PC", connection.isOnline ? "verbunden" : "offline")
                row("Ollama", store.status?.ollama == true ? "bereit" : "wartet")
                row("Läufe", "\(store.status?.runs ?? store.stats?.runCount ?? store.runs.count)")
                row("Gesamt", RunningFormat.km(store.status?.distanceKm ?? store.stats?.totalDistanceKm))
                if store.pluginMissing {
                    Text("Running-Plugin fehlt auf dem PC. NOCO AI Windows aktualisieren.")
                        .font(.caption)
                        .foregroundStyle(NOCOAITheme.danger)
                } else if let err = store.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(NOCOAITheme.danger)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Übersicht")
                    .font(.headline)
                HStack(spacing: 10) {
                    statChip("Woche", RunningFormat.km(store.stats?.thisWeekDistanceKm))
                    statChip("Monat", RunningFormat.km(store.stats?.thisMonthDistanceKm))
                    statChip("Pace", RunningFormat.pace(store.stats?.avgPaceSecPerKm))
                }
                if let route = store.stats?.mostFrequentRoute, !route.isEmpty {
                    Text("Route · \(route)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var weekCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Wochen")
                    .font(.headline)
                HStack(alignment: .bottom, spacing: 6) {
                    let maxKm = max(store.weekly.compactMap(\.distanceKm).max() ?? 1, 1)
                    ForEach(store.weekly) { point in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(accent.opacity(0.75))
                                .frame(height: max(8, CGFloat((point.distanceKm ?? 0) / maxKm) * 56))
                            Text(weekLabel(point.period))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 78)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var runsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Läufe")
                    .font(.headline)
                if store.runs.isEmpty {
                    Text("Noch keine Daten. Demo laden oder später vom iPhone importieren.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(store.runs.prefix(12).enumerated()), id: \.element.id) { index, run in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(run.title ?? run.routeName ?? "Lauf \(store.runs.count - index)")
                                    .font(.subheadline.weight(.semibold))
                                Text(RunningFormat.shortDate(run.date ?? run.startTime))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(RunningFormat.km(run.distanceKm))
                                    .font(.subheadline.weight(.semibold))
                                Text("\(RunningFormat.duration(run.durationSec)) · \(RunningFormat.pace(run.avgPaceSecPerKm))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if index < min(store.runs.count, 12) - 1 {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionsCard: some View {
        GlassCard {
            VStack(spacing: 10) {
                Button {
                    Task { await store.refresh() }
                    HapticService.light()
                } label: {
                    Label("Status", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .disabled(!connection.isOnline || store.isBusy)

                Button {
                    Task { await store.loadDemo() }
                } label: {
                    Label("Demo-Daten laden", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .disabled(!connection.isOnline || store.isBusy)

                Button {
                    Task { await store.analyze() }
                } label: {
                    Label("KI analysieren", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .disabled(!connection.isOnline || store.isBusy || store.runs.isEmpty)
            }
        }
    }

    private var askCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Frage")
                    .font(.headline)
                HStack(spacing: 8) {
                    TextField("Wie war mein letzter Lauf?", text: $question, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($askFocused)
                        .textInputAutocapitalization(.sentences)
                    Button {
                        let q = question
                        askFocused = false
                        Task { await store.ask(q) }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(accent)
                    }
                    .disabled(!connection.isOnline || store.isBusy || question.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                }
                if !store.answer.isEmpty {
                    Text(store.answer)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var analysisCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Analyse")
                    .font(.headline)
                if !store.insights.isEmpty {
                    ForEach(Array(store.insights.enumerated()), id: \.offset) { _, line in
                        Label(line, systemImage: "lightbulb")
                            .font(.caption)
                    }
                }
                if !store.recommendations.isEmpty {
                    ForEach(Array(store.recommendations.enumerated()), id: \.offset) { _, line in
                        Label(line, systemImage: "checkmark.circle")
                            .font(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var activityCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Aktivität")
                    .font(.headline)
                if store.activity.isEmpty {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(store.activity.prefix(10).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stateLabel: String {
        if !connection.isOnline { return "Offline" }
        if store.pluginMissing { return "Nicht installiert" }
        if store.status?.ollama == true { return "Online" }
        if store.status != nil { return "Server · Modell wartet" }
        return "Prüfen…"
    }

    private var stateColor: Color {
        if !connection.isOnline || store.pluginMissing { return NOCOAITheme.danger }
        if store.status?.ollama == true { return NOCOAITheme.success }
        return Color(red: 0.91, green: 0.65, blue: 0.28)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func statChip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.opacity(0.1))
        )
    }

    private func weekLabel(_ period: String?) -> String {
        guard let period, period.count >= 10 else { return "·" }
        let parts = period.prefix(10).split(separator: "-")
        guard parts.count == 3 else { return "·" }
        return "\(parts[2]).\(parts[1])"
    }
}
