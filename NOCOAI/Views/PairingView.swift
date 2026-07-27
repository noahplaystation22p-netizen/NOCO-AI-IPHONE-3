import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme

    @State private var host = ""
    @State private var port = "4747"
    @State private var pin = ""
    @State private var showQRScanner = false
    @FocusState private var focusedField: Field?

    private enum Field { case host, port, pin }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                pairingCard
                hintsCard
            }
            .padding(20)
        }
        .nocoBackground()
        .onAppear {
            applyStoredValues()
            connection.prepareLocalNetworkAccess(host: host.isEmpty ? "192.168.0.1" : host, port: Int(port) ?? 4747)
        }
        .onChange(of: connection.pendingDeepLink?.host) { _, _ in
            applyDeepLinkIfNeeded()
        }
        .sheet(isPresented: $showQRScanner) {
            NavigationStack {
                QRScannerView { code in
                    connection.applyQRCode(code)
                    applyDeepLinkIfNeeded()
                }
                .ignoresSafeArea()
                .navigationTitle("QR scannen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { showQRScanner = false }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            BrandLogo(size: 96)
            Text("NOCO AI")
                .font(.largeTitle.bold())
                .foregroundStyle(NOCOAITheme.primaryText(for: scheme))
            Text("Verbinde dein iPhone mit deinem Windows-PC")
                .font(.subheadline)
                .foregroundStyle(NOCOAITheme.secondaryText(for: scheme))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
    }

    private var pairingCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Kopplung")
                    .font(.headline)

                Text("NOCO AI auf dem PC → Statusleiste → iPhone. Dort findest du IP, PIN und QR-Code.")
                    .font(.footnote)
                    .foregroundStyle(NOCOAITheme.secondaryText(for: scheme))

                TextField("Nur IP — z. B. 192.168.178.197", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
                    .focused($focusedField, equals: .host)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(fieldBackground)
                    .onChange(of: host) { _, newValue in
                        sanitizeHostField(newValue)
                    }

                HStack(spacing: 12) {
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .port)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(fieldBackground)
                        .frame(width: 100)

                    TextField("PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .pin)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(fieldBackground)
                }

                if let hint = connection.localNetworkHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(NOCOAITheme.accent)
                }

                Text("Die PIN wechselt alle 15 Minuten. Bei Fehler neue PIN in NOCO AI holen.")
                    .font(.caption)
                    .foregroundStyle(NOCOAITheme.secondaryText(for: scheme))

                if let ping = connection.pingMessage {
                    Text(ping)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(pingColor(ping))
                }

                if let error = connection.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(NOCOAITheme.danger)
                }

                HStack(spacing: 10) {
                    Button {
                        focusedField = nil
                        Task {
                            _ = await connection.testConnection(
                                host: host,
                                port: Int(port) ?? 4747
                            )
                        }
                    } label: {
                        HStack {
                            if connection.isPinging {
                                ProgressView().scaleEffect(0.8)
                            }
                            Text("Verbindung testen")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .disabled(host.isEmpty || connection.isPinging)

                    Button {
                        showQRScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.title3)
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    focusedField = nil
                    Task {
                        await connection.pair(
                            host: host,
                            port: Int(port) ?? 4747,
                            pin: pin
                        )
                    }
                } label: {
                    HStack {
                        if connection.isRefreshing {
                            ProgressView().tint(.white)
                        }
                        Text(connection.isRefreshing ? "Verbinde…" : "Mit PC koppeln")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(NOCOAITheme.accent)
                .disabled(host.isEmpty || pin.isEmpty || connection.isRefreshing)
            }
        }
    }

    private var hintsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Hinweise", systemImage: "info.circle")
                    .font(.headline)
                Text("• PC und iPhone im gleichen WLAN\n• Windows-Firewall Port 4747 erlauben\n• NOCO AI muss auf dem PC laufen\n• Nur Companion-Port 4747 — keine lokale KI auf dem iPhone")
                    .font(.footnote)
                    .foregroundStyle(NOCOAITheme.secondaryText(for: scheme))
            }
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06))
    }

    private func pingColor(_ message: String) -> Color {
        message.contains("✓") ? NOCOAITheme.success : NOCOAITheme.danger
    }

    private func sanitizeHostField(_ value: String) {
        guard value.contains("http") || value.contains("/") || value.contains(":") else { return }
        if let parsed = HostSanitizer.parse(value, defaultPort: Int(port) ?? 4747) {
            host = parsed.host
            if let parsedPort = parsed.port {
                port = String(parsedPort)
            }
        }
    }

    private func applyStoredValues() {
        if host.isEmpty { host = HostSanitizer.hostOnly(connection.serverHost) }
        if port == "4747", connection.serverPort != 4747 {
            port = String(connection.serverPort)
        }
        applyDeepLinkIfNeeded()
    }

    private func applyDeepLinkIfNeeded() {
        guard let link = connection.pendingDeepLink else { return }
        host = link.host
        port = String(link.port)
        if let linkPin = link.pin, !linkPin.isEmpty {
            pin = linkPin
        }
        connection.pendingDeepLink = nil
    }
}
