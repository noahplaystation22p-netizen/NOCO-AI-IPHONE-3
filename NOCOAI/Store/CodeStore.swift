import Foundation

@MainActor
final class CodeStore: ObservableObject {
    @Published var sessions: [CodeSession] = []
    @Published var activeSession: CodeSession?
    @Published var messages: [ChatMessage] = []
    @Published var previewCode = ""
    @Published var isSending = false

    private var api: CompanionAPI?

    func bind(api: CompanionAPI?) {
        self.api = api
    }

    func loadSessions() async {
        guard let api else { return }
        sessions = (try? await api.fetchCodeSessions()) ?? []
    }

    func createSession(language: String = "swift") async {
        guard let api else { return }
        if let session = try? await api.createCodeSession(title: "Code Assist", language: language) {
            activeSession = session
            previewCode = session.preview ?? ""
            messages = []
            await loadSessions()
        }
    }

    func select(_ session: CodeSession) {
        activeSession = session
        previewCode = session.preview ?? ""
        messages = []
    }

    func initWorkspace() async {
        guard let api, let id = activeSession?.id else { return }
        try? await api.initCodeWorkspace(sessionId: id)
        HapticService.success()
    }

    func send(_ text: String) async {
        guard let api, let sessionId = activeSession?.id, !isSending else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSending = true
        messages.append(ChatMessage(role: .user, text: trimmed))
        let assistant = ChatMessage(role: .assistant, text: "", isStreaming: true)
        messages.append(assistant)
        let assistantID = assistant.id

        do {
            for try await chunk in api.streamCodeChat(sessionId: sessionId, message: trimmed) {
                if let idx = messages.firstIndex(where: { $0.id == assistantID }) {
                    messages[idx].text += chunk
                }
            }
            if let idx = messages.firstIndex(where: { $0.id == assistantID }) {
                messages[idx].isStreaming = false
                if messages[idx].text.contains("```") {
                    previewCode = extractCode(from: messages[idx].text) ?? previewCode
                }
            }
            HapticService.success()
            await loadSessions()
        } catch {
            HapticService.error()
        }
        isSending = false
    }

    private func extractCode(from markdown: String) -> String? {
        guard let start = markdown.range(of: "```"),
              let end = markdown.range(of: "```", range: start.upperBound..<markdown.endIndex) else { return nil }
        var code = String(markdown[start.upperBound..<end.lowerBound])
        if let firstLine = code.components(separatedBy: "\n").first, firstLine.allSatisfy({ $0.isLetter }) {
            code = code.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
        }
        return code.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
