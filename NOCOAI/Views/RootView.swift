import SwiftUI

struct RootView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if connection.isPaired {
                MainTabView()
            } else {
                PairingView()
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: connection.isPaired)
        .alert(
            "NOCO PC nicht im lokalen Netzwerk gefunden.",
            isPresented: $connection.showRemotePrompt
        ) {
            Button("Ja") {
                Task { await connection.confirmRemoteConnection() }
            }
            Button("Nein", role: .cancel) {
                connection.declineRemoteConnection()
            }
        } message: {
            Text("Remote Verbindung über Tailscale verwenden?\n\nVoraussetzung: Tailscale auf iPhone und PC mit demselben Konto, und auf dem PC „Remote Zugriff aktivieren“.")
        }
        .alert(
            "Lokale Verbindung verfügbar.",
            isPresented: $connection.showLocalAvailablePrompt
        ) {
            Button("Wechseln") {
                Task { await connection.confirmLocalConnection() }
            }
            Button("Später", role: .cancel) {
                connection.declineLocalSwitch()
            }
        } message: {
            Text("Dein NOCO-PC ist wieder im WLAN erreichbar. Zur schnelleren lokalen Verbindung wechseln?")
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                connection.onForeground()
            case .background, .inactive:
                connection.onBackground()
            @unknown default:
                break
            }
        }
    }
}
