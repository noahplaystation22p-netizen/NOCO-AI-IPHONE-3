import SwiftUI
import UIKit

struct ConnectionDiagnoseView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @ObservedObject private var diagnostics = ConnectionDiagnostics.shared
    @State private var copyStatus = ""

    private var snap: ConnectionProbeSnapshot { diagnostics.snapshot }

    var body: some View {
        List {
            statusSection
            liveKnowledgeSection
            detailsSection
            testSection
            logSection
            faqSection
        }
        .navigationTitle("Diagnose")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if diagnostics.logLines.isEmpty {
                await diagnostics.runFullProbe(connection: connection)
            }
            await connection.refreshStatus(showLoading: false)
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section("Verbindung") {
            let mode = connectionModeLabel
            HStack {
                Circle()
                    .fill(mode.color)
                    .frame(width: 10, height: 10)
                Text(mode.title)
                    .font(.body.weight(.semibold))
                Spacer()
                if diagnostics.isRunning || snap.connectingInProgress {
                    ProgressView()
                }
            }

            if snap.connectingInProgress || diagnostics.isRunning {
                Text("Verbindungstest läuft…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !snap.summary.isEmpty {
                Text(snap.summary)
                    .font(.subheadline)
            }
        }
    }

    private var connectionModeLabel: (title: String, color: Color) {
        if diagnostics.isRunning || snap.connectingInProgress {
            return ("Diagnose läuft…", .orange)
        }
        if connection.isOnline, connection.activePath == .local {
            return ("Local Network", NOCOAITheme.success)
        }
        if connection.isOnline, connection.activePath == .remote {
            return ("Tailscale", .blue)
        }
        if snap.localReachable == true {
            return ("Local Network", NOCOAITheme.success)
        }
        if snap.remoteReachable == true {
            return ("Tailscale", .blue)
        }
        return ("Offline", .red)
    }

    private var liveKnowledgeSection: some View {
        let lk = connection.status.liveKnowledge
        return Section("Live Knowledge") {
            HStack {
                Circle()
                    .fill(trafficColor(lk?.webAvailable))
                    .frame(width: 10, height: 10)
                Text("Web: \(availLabel(lk?.webAvailable))")
                Spacer()
            }
            HStack {
                Circle()
                    .fill(trafficColor(lk?.searchAvailable))
                    .frame(width: 10, height: 10)
                Text("Search: \(availLabel(lk?.searchAvailable))")
                Spacer()
            }
            LabeledContent("Last Search", value: shortTime(lk?.lastSearchAt) ?? "—")
            LabeledContent(
                "Response Time",
                value: lk?.lastLatencyMs.map { "\(Int($0)) ms" } ?? "—"
            )
            LabeledContent("Provider", value: lk?.provider ?? "—")
            LabeledContent(
                "Cache",
                value: lk?.cacheEntries.map { "\($0) Einträge" } ?? "—"
            )
            if let reason = lk?.lastReason, !reason.isEmpty {
                LabeledContent("Last Reason", value: reason)
            }
            if let queries = lk?.lastQueries, !queries.isEmpty {
                Text(queries.prefix(2).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func trafficColor(_ value: Bool?) -> Color {
        guard let value else { return .orange }
        return value ? NOCOAITheme.success : .red
    }

    private func availLabel(_ value: Bool?) -> String {
        guard let value else { return "Unknown" }
        return value ? "Available" : "Unavailable"
    }

    private func shortTime(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        if let d = ISO8601DateFormatter().date(from: iso) {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f.string(from: d)
        }
        return String(iso.suffix(8))
    }

    private var detailsSection: some View {
        Section("Details") {
            LabeledContent("Aktiver Host", value: hostPort(snap.activeHost))
            LabeledContent("Methode", value: snap.pathKind)
            LabeledContent("Server", value: reachLabel(snap.serverReachable))
            LabeledContent("TCP", value: tcpLabel(snap.tcpOK))
            LabeledContent("HTTP", value: snap.httpLabel)
            LabeledContent("Tailscale", value: snap.tailscaleDetected ? "Detected" : "Not detected")
            LabeledContent("Antwortzeit", value: snap.responseMs.map { "\($0) ms" } ?? "—")
            LabeledContent("Fehlercode", value: snap.failureCode.rawValue)
            if !connection.localHost.isEmpty {
                LabeledContent("Lokal", value: "\(connection.localHost):\(connection.serverPort)")
            }
            if !connection.remoteHost.isEmpty {
                LabeledContent("Remote", value: "\(connection.remoteHost):\(connection.serverPort)")
            }
        }
    }

    private var testSection: some View {
        Section {
            Button {
                Task {
                    HapticService.open()
                    await diagnostics.runFullProbe(connection: connection)
                    if snap.failureCode == .ok {
                        HapticService.success()
                    } else {
                        HapticService.error()
                    }
                }
            } label: {
                Label(
                    diagnostics.isRunning ? "Teste…" : "Verbindung testen",
                    systemImage: "stethoscope"
                )
            }
            .disabled(diagnostics.isRunning)

            Button {
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
                let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
                UIPasteboard.general.string = diagnostics.exportText(
                    appVersion: "\(ver) (\(build))",
                    connection: connection
                )
                copyStatus = "Diagnose kopiert"
                HapticService.success()
            } label: {
                Label("Diagnose kopieren", systemImage: "doc.on.doc")
            }

            Button(role: .destructive) {
                diagnostics.clearLog()
                copyStatus = "Log geleert"
                HapticService.soft()
            } label: {
                Label("Log leeren", systemImage: "trash")
            }

            if !copyStatus.isEmpty {
                Text(copyStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Tests")
        } footer: {
            Text("Testet nacheinander: Local → Tailscale → TCP → HTTP/API. Keine Tokens oder Passwörter werden geloggt.")
        }
    }

    private var logSection: some View {
        Section("Live-Log") {
            if diagnostics.logLines.isEmpty {
                Text("Noch keine Einträge — „Verbindung testen“ tippen.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(diagnostics.logLines.suffix(80).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var faqSection: some View {
        Section("Häufige Probleme") {
            faq(
                "Tailscale nicht verbunden",
                "Beide Geräte müssen im gleichen Tailscale-Netzwerk angemeldet sein. iPhone: Tailscale-VPN an. PC: „Remote starten“."
            )
            faq(
                "PC nicht erreichbar",
                "Tailscale läuft ggf. nicht auf dem Windows-PC oder der PC ist ausgeschaltet."
            )
            faq(
                "Port nicht erreichbar",
                "NOCO Server läuft ggf. nicht oder die Windows-Firewall blockiert Port \(connection.serverPort)."
            )
            faq(
                "HTTP durch iOS blockiert",
                "ATS muss Cleartext für private Tailscale-IPs erlauben. Neueste IPA installieren (Build 109+)."
            )
            faq(
                "Falscher Port",
                "Die Tailscale-IP allein reicht nicht — NOCO erwartet Port \(connection.serverPort)."
            )
            faq(
                "Server hört nur auf localhost",
                "Der Companion muss auf 0.0.0.0 lauschen (Standard in NOCO AI X). Nur 127.0.0.1 = kein Tailscale-Zugriff."
            )
            faq(
                "HTTPS/TLS-Problem",
                "Keine https:// eingeben. NOCO nutzt HTTP innerhalb von WLAN/Tailscale — kein öffentlicher Port."
            )
        }
    }

    // MARK: - Helpers

    private func faq(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(body).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func hostPort(_ host: String) -> String {
        guard !host.isEmpty else { return "—" }
        return "\(host):\(connection.serverPort)"
    }

    private func reachLabel(_ value: Bool?) -> String {
        guard let value else { return "—" }
        return value ? "Reachable" : "Unreachable"
    }

    private func tcpLabel(_ value: Bool?) -> String {
        guard let value else { return "—" }
        return value ? "Connected" : "Failed"
    }
}
