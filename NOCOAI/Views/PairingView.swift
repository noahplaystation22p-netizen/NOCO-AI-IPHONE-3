import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.colorScheme) private var scheme

    @State private var showQRScanner = false
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
            FloatingIntelligenceDots(count: 6)
                .opacity(0.4)

            VStack(spacing: 22) {
                Spacer(minLength: 36)

                ZStack {
                    // Soft rainbow bloom behind logo
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: NOCORainbow.flow.map { $0.opacity(0.55) },
                                center: .center
                            )
                        )
                        .frame(width: 160, height: 160)
                        .blur(radius: 28)
                        .opacity(0.75)
                    PixelSphereView(size: 180, intensity: 0.75, phase: isPairingFromQR ? .locking : .idle, pixelCount: 64)
                        .opacity(0.7)
                    BrandLogo(size: 80)
                        .scaleEffect(appear ? 1 : 0.88)
                }
                .frame(height: 180)

                VStack(spacing: 8) {
                    Text("NOCO AI")
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                    Text("Scanne den QR-Code auf deinem PC")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 12)

                Button {
                    HapticService.open()
                    showQRScanner = true
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 46, weight: .light))
                            .symbolEffect(.pulse, options: .repeating, isActive: !isPairingFromQR)
                        Text(isPairingFromQR || connection.isRefreshing ? "Verbinde…" : "QR-Code scannen")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                    .background {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .shadow(color: NOCORainbow.violet.opacity(0.35), radius: 28, y: 10)
                    }
                    .intelligenceShimmerBorder()
                }
                .buttonStyle(.plain)
                .disabled(isPairingFromQR || connection.isRefreshing)
                .scaleEffect(appear ? 1 : 0.96)

                if isPairingFromQR || connection.isRefreshing {
                    HStack(spacing: 10) {
                        IntelligenceThinkingDots()
                            .scaleEffect(0.85)
                        Text("Verbinde mit PC…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                }

                if let error = connection.lastError {
                    Text(WatchUserFacingError.sanitize(error))
                        .font(.footnote)
                        .foregroundStyle(NOCOAITheme.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
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
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            connection.prepareLocalNetworkAccess(host: "192.168.0.1", port: 4747)
            applyDeepLinkIfNeeded()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                appear = true
            }
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
            TextField("IP — WLAN oder Tailscale 100.x", text: $host)
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
        HapticService.light()
        await connection.pairFromQR(code)
        if connection.isPaired {
            HapticService.pairSuccess()
            showQRScanner = false
        } else {
            HapticService.error()
            showQRScanner = true
        }
    }

    private func applyDeepLinkIfNeeded() {
        guard let link = connection.pendingDeepLink else { return }
        host = link.host
        port = String(link.port)
        if let linkPin = link.pin, !linkPin.isEmpty {
            pin = linkPin
            Task {
                await connection.pair(
                    host: link.host,
                    port: link.port,
                    pin: linkPin,
                    remoteHint: link.remoteHost,
                    lanHint: link.lanHost
                )
            }
        }
        connection.pendingDeepLink = nil
    }
}
