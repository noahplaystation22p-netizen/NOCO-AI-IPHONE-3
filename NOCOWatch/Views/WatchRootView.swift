import SwiftUI

struct WatchRootView: View {
    @StateObject private var controller = WatchController()
    @State private var crownIndex: Double = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $controller.section) {
            WatchAskView()
                .tag(WatchSection.ask)
            WatchVoiceView()
                .tag(WatchSection.voice)
            WatchLastAnswerView()
                .tag(WatchSection.last)
            WatchStatusView()
                .tag(WatchSection.status)
        }
        .tabViewStyle(.verticalPage)
        .background(Color.black)
        .onAppear { controller.onAppear() }
        .onDisappear { controller.onDisappear() }
        .environmentObject(controller)
        .focusable(true)
        .digitalCrownRotation(
            $crownIndex,
            from: 0,
            through: Double(WatchSection.allCases.count - 1),
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: false
        )
        .onChange(of: crownIndex) { _, newValue in
            controller.snapCrown(to: Int(newValue.rounded()))
        }
        .onChange(of: controller.section) { _, newSection in
            if let idx = WatchSection.allCases.firstIndex(of: newSection) {
                crownIndex = Double(idx)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                // Don't leave thinking/speaking animations stuck.
                if controller.voice.isActive == false,
                   controller.localPhase == .thinking || controller.localPhase == .speaking {
                    controller.localPhase = .idle
                }
            }
            if phase == .active {
                controller.session.refreshStatus()
            }
        }
    }
}

struct WatchSectionHeader: View {
    let title: String
    let phase: WatchStatusSnapshot.Phase

    var body: some View {
        VStack(spacing: 6) {
            WatchIntelligenceCore(phase: phase, diameter: 72)
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.top, 4)
    }
}
