import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme

    @State private var host = ""
    @State private var port = "4747"
    @State private var pin = ""
    @FocusState private var focusedField: Field?

    private enum Field { case host, port, pin }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
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

                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Kopplung")
                            .font(.headline)

                        Text("Öffne NOCO AI auf dem PC → Statusleiste → iPhone. Dort findest du IP und PIN.")
                            .font(.footnote)
                            .foregroundStyle(NOCOAITheme.secondaryText(for: scheme))

                        TextField("PC-IP (z. B. 192.168.178.197)", text: $host)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .host)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))

                        HStack(spacing: 12) {
                            TextField("Port", text: $port)
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .port)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
                                .frame(width: 100)

                            TextField("PIN", text: $pin)
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .pin)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
                        }

                        if let error = connection.lastError {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(NOCOAITheme.danger)
                        }

                        Button {
                            focusedField = nil
                            connection.serverHost = host
                            connection.serverPort = Int(port) ?? 4747
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

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Hinweise", systemImage: "info.circle")
                            .font(.headline)
                        Text("• PC und iPhone im gleichen WLAN\n• Windows-Firewall Port 4747 erlauben\n• NOCO AI muss auf dem PC laufen\n• Keine lokale KI auf dem iPhone")
                            .font(.footnote)
                            .foregroundStyle(NOCOAITheme.secondaryText(for: scheme))
                    }
                }
            }
            .padding(20)
        }
        .nocoBackground()
        .onAppear {
            if host.isEmpty { host = connection.serverHost }
            if port == "4747", connection.serverPort != 4747 {
                port = String(connection.serverPort)
            }
        }
    }
}
