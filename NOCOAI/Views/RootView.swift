import SwiftUI

struct RootView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("nocoai.onboardingDone") private var onboardingDone = false

    var body: some View {
        Group {
            if connection.isPaired {
                if onboardingDone {
                    MainTabView()
                } else {
                    OnboardingWelcomeView {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                            onboardingDone = true
                        }
                    }
                }
            } else {
                PairingView()
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: connection.isPaired)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: onboardingDone)
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
