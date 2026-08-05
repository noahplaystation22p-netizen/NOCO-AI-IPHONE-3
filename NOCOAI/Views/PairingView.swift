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
            FloatingIntelligenceDots(count: 4)
                .opacity(0.35)

            VStack(spacing: 24) {
                Spacer(minLength: 28)

                ZStack {
                    PixelSphereView(size: 200, intensity: 0.7, phase: isPairingFromQR ? .locking : .idle, pixelCount: 72)
                        .opacity(0.75)
                    BrandLogo(size: 84)
                        .scaleEffect(appear ? 1 : 0.88)
                }
                .frame(height: 200)

                VStack(spacing: 10) {
                    Text("NOCO AI")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                    Text("Scanne den QR-Code auf deinem PC.\nPixel reagieren, sobald er erkannt wird.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    PairingPulseSteps()
                        .padding(.top, 6)
                }
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 14)

                Button {
                    HapticService.medium()
                    showQRScanner = true
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 44, weight: .light))
                            .symbolEffect(.pulse, options: .repeating, isActive: !isPairingFromQR)
                        Text(isPairingFromQR || connection.isRefreshing ? "Verbinde mit PC…" : "QR-Code scannen")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
                    .background {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .shadow(color: NOCOAITheme.glowPrimary.opacity(0.35), radius: 28, y: 10)
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
                        Text("NOCO Sync…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if let error = connection.lastError {
                    Text(error)
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

                Text("PC · gleiches WLAN · NOCO AI X")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 22)
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
