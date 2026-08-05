import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme

    @State private var showQRScanner = true
    @State private var isPairingFromQR = false
    @State private var host = ""
    @State private var port = "4747"
    @State private var pin = ""
    @State private var showManual = false
    @FocusState private var focusedField: Field?

    private enum Field { case host, pin }

    var body: some View {
        ZStack {
            NOCOAITheme.intelligenceBackground(for: scheme).ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer(minLength: 40)

                VStack(spacing: 14) {
                    BrandLogo(size: 72)
                    Text("NOCO AI")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                    Text("Scanne den QR-Code auf deinem PC.\nDanach einfach fragen.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    HapticService.medium()
                    showQRScanner = true
                } label: {
                    VStack(spacing: 14) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 44, weight: .light))
                        Text(isPairingFromQR || connection.isRefreshing ? "Verbinde…" : "QR-Code scannen")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isPairingFromQR || connection.isRefreshing)

                if let error = connection.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(NOCOAITheme.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if let ping = connection.pingMessage {
                    Text(ping)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(ping.contains("✓") ? NOCOAITheme.success : NOCOAITheme.danger)
                }

                Button(showManual ? "Manuell ausblenden" : "Manuell mit PIN") {
                    withAnimation { showManual.toggle() }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

                if showManual {
                    manualCard
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer()

                Text("PC und iPhone im gleichen WLAN · NOCO AI X muss laufen")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            connection.prepareLocalNetworkAccess(host: "192.168.0.1", port: 4747)
            applyDeepLinkIfNeeded()
        }
        .onChange(of: connection.pendingDeepLink?.host) { _, _ in
            applyDeepLinkIfNeeded()
        }
        .fullScreenCover(isPresented: $showQRScanner) {
            NavigationStack {
                QRScannerView { code in
                    Task { await pairFromQR(code) }
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

    private var manualCard: some View {
        VStack(spacing: 12) {
            TextField("IP — z. B. 192.168.178.197", text: $host)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.numbersAndPunctuation)
                .focused($focusedField, equals: .host)
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

            TextField("PIN vom PC", text: $pin)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .pin)
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

            Button {
                focusedField = nil
                Task {
                    await connection.pair(host: host, port: Int(port) ?? 4747, pin: pin)
                }
            } label: {
                Text("Verbinden")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(NOCOAITheme.accent)
            .disabled(host.isEmpty || pin.isEmpty || connection.isRefreshing)
        }
    }

    private func pairFromQR(_ code: String) async {
        isPairingFromQR = true
        defer { isPairingFromQR = false }
        await connection.pairFromQR(code)
        if !connection.isPaired {
            showQRScanner = true
        }
    }

    private func applyDeepLinkIfNeeded() {
        guard let link = connection.pendingDeepLink else { return }
        host = link.host
        port = String(link.port)
        if let linkPin = link.pin, !linkPin.isEmpty {
            pin = linkPin
            Task { await connection.pair(host: link.host, port: link.port, pin: linkPin) }
        }
        connection.pendingDeepLink = nil
    }
}
