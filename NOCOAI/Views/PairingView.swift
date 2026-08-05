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
    @State private var appear = false
    @FocusState private var focusedField: Field?

    private enum Field { case host, pin }

    var body: some View {
        ZStack {
            IntelligenceAtmosphere()
            FloatingIntelligenceDots(count: 14)

            VStack(spacing: 26) {
                Spacer(minLength: 36)

                VStack(spacing: 14) {
                    BrandLogo(size: 78)
                        .shadow(color: NOCOAITheme.glowPrimary.opacity(0.55), radius: appear ? 28 : 8)
                        .scaleEffect(appear ? 1 : 0.92)
                    Text("NOCO AI")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                    Text("Scanne den QR-Code auf deinem PC.\nDann einfach fragen — wie ChatGPT.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    PairingPulseSteps()
                        .padding(.top, 4)
                }
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 12)

                Button {
                    HapticService.medium()
                    showQRScanner = true
                } label: {
                    VStack(spacing: 14) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 46, weight: .light))
                            .symbolEffect(.pulse, options: .repeating, isActive: !isPairingFromQR)
                        Text(isPairingFromQR || connection.isRefreshing ? "Verbinde mit PC…" : "QR-Code scannen")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 38)
                    .background {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 30, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                NOCOAITheme.glowPrimary.opacity(0.7),
                                                NOCOAITheme.glowSecondary.opacity(0.4),
                                                NOCOAITheme.glowAccent.opacity(0.35)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.2
                                    )
                            )
                            .shadow(color: NOCOAITheme.glowPrimary.opacity(0.35), radius: 24, y: 8)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isPairingFromQR || connection.isRefreshing)
                .scaleEffect(appear ? 1 : 0.96)

                if isPairingFromQR || connection.isRefreshing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Cloud-Sync wird aufgebaut…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                }

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
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showManual.toggle() }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

                if showManual {
                    manualCard
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer()

                Text("PC und iPhone · gleiches WLAN · NOCO AI X")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            connection.prepareLocalNetworkAccess(host: "192.168.0.1", port: 4747)
            applyDeepLinkIfNeeded()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                appear = true
            }
        }
        .onChange(of: connection.pendingDeepLink?.host) { _, _ in
            applyDeepLinkIfNeeded()
        }
        .fullScreenCover(isPresented: $showQRScanner) {
            NavigationStack {
                ZStack {
                    QRScannerView { code in
                        Task { await pairFromQR(code) }
                    }
                    FloatingIntelligenceDots(count: 8)
                        .opacity(0.55)
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
