import Combine
import Foundation

@MainActor
final class RunningPluginStore: ObservableObject {
    @Published var status: RunningStatusResponse?
    @Published var stats: RunningStats?
    @Published var weekly: [RunningWeeklyPoint] = []
    @Published var runs: [RunningRun] = []
    @Published var activity: [String] = []
    @Published var answer: String = ""
    @Published var analysisSummary: String = ""
    @Published var insights: [String] = []
    @Published var recommendations: [String] = []
    @Published var lastError: String?
    @Published var isBusy = false
    @Published var pluginMissing = false

    var conversationId: String?

    private var apiProvider: (() -> CompanionAPI?)?

    func bind(apiProvider: @escaping () -> CompanionAPI?) {
        self.apiProvider = apiProvider
    }

    func refresh() async {
        guard let api = apiProvider?() else {
            lastError = "PC offline — bitte koppeln."
            return
        }
        lastError = nil
        pluginMissing = false
        do {
            async let statusTask = api.fetchRunningStatus()
            async let dataTask = api.fetchRunningData()
            async let statsTask = api.fetchRunningStats()
            async let activityTask = api.fetchRunningActivity()
            status = try await statusTask
            runs = (try await dataTask).runs ?? []
            let statsBody = try await statsTask
            stats = statsBody.stats
            weekly = statsBody.series?.weeklyDistance ?? []
            activity = (try await activityTask).lines ?? []
        } catch {
            applyFailure(error)
        }
    }

    func loadDemo() async {
        guard let api = apiProvider?() else { return }
        isBusy = true
        defer { isBusy = false }
        lastError = nil
        do {
            _ = try await api.loadRunningDemo()
            HapticService.success()
            await refresh()
        } catch {
            applyFailure(error)
            HapticService.error()
        }
    }

    func ask(_ question: String) async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2, let api = apiProvider?() else { return }
        isBusy = true
        defer { isBusy = false }
        lastError = nil
        do {
            let r = try await api.askRunning(question: q, conversationId: conversationId)
            conversationId = r.conversationId ?? conversationId
            answer = r.answer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if answer.isEmpty {
                lastError = "Keine Antwort vom Modell."
            }
            HapticService.success()
            await refreshQuiet()
        } catch {
            applyFailure(error)
            HapticService.error()
        }
    }

    func analyze() async {
        guard let api = apiProvider?() else { return }
        isBusy = true
        defer { isBusy = false }
        lastError = nil
        do {
            let r = try await api.analyzeRunning(conversationId: conversationId)
            analysisSummary = r.analysis?.summary ?? ""
            insights = r.analysis?.insights ?? []
            recommendations = r.analysis?.recommendations ?? []
            if analysisSummary.isEmpty {
                lastError = "Analyse ohne Inhalt."
            } else {
                answer = analysisSummary
            }
            HapticService.success()
            await refresh()
        } catch {
            applyFailure(error)
            HapticService.error()
        }
    }

    private func refreshQuiet() async {
        guard let api = apiProvider?() else { return }
        if let lines = try? await api.fetchRunningActivity() {
            activity = lines.lines ?? activity
        }
        if let s = try? await api.fetchRunningStatus() {
            status = s
        }
    }

    private func applyFailure(_ error: Error) {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        lastError = text
        if let api = error as? CompanionAPIError {
            pluginMissing = api.failureCode == .httpError404
        } else {
            pluginMissing = text.lowercased().contains("aktualisieren") || text.lowercased().contains("unbekannte")
        }
    }
}
