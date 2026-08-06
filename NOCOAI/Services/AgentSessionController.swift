import Combine
import Foundation

@MainActor
final class AgentSessionController: ObservableObject {
    @Published var mode: AgentMode = .assistant
    @Published var kind: AgentKind = .general
    @Published var tasks: [AgentTask] = []
    @Published var activeTask: AgentTask?
    @Published var draftGoal = ""
    @Published var isWorking = false
    @Published var statusLine = "Bereit"
    @Published var lastError: String?

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
                try? await Task.sleep(nanoseconds: 3_500_000_000)
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
            let list = try await api.listAgentTasks()
            tasks = list
            if let id = activeTask?.id, let fresh = list.first(where: { $0.id == id }) {
                activeTask = fresh
            }
            statusLine = list.first(where: { $0.status == "running" || $0.status == "awaiting_confirmation" })
                .map { "Aktiv: \($0.statusEnum.label)" } ?? "Bereit"
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func refreshQuiet() async {
        guard let api = apiProvider?() else { return }
        guard let list = try? await api.listAgentTasks() else { return }
        tasks = list
        if let id = activeTask?.id, let fresh = list.first(where: { $0.id == id }) {
            let prev = activeTask?.status
            activeTask = fresh
            if prev != fresh.status {
                if fresh.status == "completed" {
                    HapticService.success()
                    await AppNotificationService.notifyAgentReady(goal: fresh.goal)
                } else if fresh.status == "awaiting_confirmation" {
                    HapticService.rigid()
                    await AppNotificationService.notifyAgentNeedsConfirm(goal: fresh.goal)
                }
            }
        }
    }

    func startGoal() async {
        let goal = draftGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty else { return }
        guard let api = apiProvider?() else {
            lastError = "Companion offline — bitte koppeln."
            HapticService.error()
            return
        }
        isWorking = true
        statusLine = "Plant & startet…"
        lastError = nil
        HapticService.open()
        defer { isWorking = false }
        do {
            let task = try await api.createAgentTask(goal: goal, mode: mode, kind: kind, autoRun: true)
            draftGoal = ""
            activeTask = task
            await refresh()
            statusLine = task.statusEnum.label
            if task.status == "completed" {
                HapticService.success()
                await AppNotificationService.notifyAgentReady(goal: task.goal)
            } else if task.status == "awaiting_confirmation" {
                HapticService.rigid()
            } else {
                HapticService.messageReceived()
            }
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusLine = "Fehler"
            HapticService.error()
        }
    }

    func select(_ task: AgentTask) {
        activeTask = task
        HapticService.selection()
    }

    func confirm(allow: Bool) async {
        guard let task = activeTask, let pending = task.pendingConfirm else { return }
        guard let api = apiProvider?() else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let updated = try await api.confirmAgentStep(taskId: task.id, stepId: pending.stepId, allow: allow)
            activeTask = updated
            await refresh()
            HapticService.success()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            HapticService.error()
        }
    }

    func cancelActive() async {
        guard let task = activeTask else { return }
        guard let api = apiProvider?() else { return }
        do {
            activeTask = try await api.cancelAgentTask(id: task.id)
            await refresh()
            HapticService.soft()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func continueRun() async {
        guard let task = activeTask else { return }
        guard let api = apiProvider?() else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            activeTask = try await api.runAgentTask(id: task.id)
            await refresh()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
