import Combine
import Foundation

@MainActor
final class ComputerControlController: ObservableObject {
    @Published var status: ComputerControlStatus?
    @Published var isWorking = false
    @Published var lastError: String?
    @Published var draftGoal = ""

    private var apiProvider: (() -> CompanionAPI?)?
    private var pollTask: Task<Void, Never>?

    func bind(apiProvider: @escaping () -> CompanionAPI?) {
        self.apiProvider = apiProvider
    }

    func clearError() { lastError = nil }

    func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshQuiet()
                try? await Task.sleep(nanoseconds: 2_800_000_000)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        guard let api = apiProvider?() else {
            lastError = "Companion offline — bitte koppeln."
            return
        }
        do {
            status = try await api.fetchComputerControlStatus()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func refreshQuiet() async {
        guard let api = apiProvider?() else { return }
        if let s = try? await api.fetchComputerControlStatus() {
            status = s
        }
    }

    func setEnabled(_ enabled: Bool) async {
        guard let api = apiProvider?() else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            status = try await api.setComputerControlPermission(
                enabled: enabled,
                allowMouse: enabled,
                allowKeyboard: enabled,
                allowOpenApps: enabled,
                allowWindowFocus: true,
                confirmEveryInput: true
            )
            HapticService.success()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            HapticService.error()
        }
    }

    func pause() async {
        guard let api = apiProvider?() else { return }
        status = try? await api.pauseComputerControl()
        HapticService.soft()
    }

    func resume() async {
        guard let api = apiProvider?() else { return }
        status = try? await api.resumeComputerControl()
        HapticService.open()
    }

    func analyzeScreen() async {
        guard let api = apiProvider?() else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await api.executeComputerAction(action: "analyze_screen", extras: [
                "question": "Welche Buttons, Dialoge und Texte sind sichtbar? Nächste sinnvolle Aktion?"
            ])
            await refresh()
            HapticService.messageReceived()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            HapticService.error()
        }
    }

    func startComputerGoal(via agent: AgentSessionController) async {
        let goal = draftGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty else { return }
        agent.mode = .automation
        agent.kind = .general
        agent.qualityProfile = .accurate
        agent.draftGoal = "Computer Control: \(goal)"
        draftGoal = ""
        await agent.startGoal()
    }
}
