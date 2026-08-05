import SwiftUI
import UIKit

@MainActor
final class KeyboardViewModel: ObservableObject {
    @Published var hasFullAccess = false
    @Published var isConfigured = false
    @Published var isProcessing = false
    @Published var statusLine = "Markiere Text oder tippe — dann Aktion wählen"
    @Published var shiftOn = false
    @Published var capsLock = false
    @Published var showingNumbers = false
    @Published var lastError: String?

    private weak var controller: KeyboardViewController?
    private var snapshotBefore = ""
    private var snapshotSelected = ""
    private var runTask: Task<Void, Never>?

    func bind(controller: KeyboardViewController) {
        self.controller = controller
        refreshAccess()
    }

    func refreshAccess() {
        CompanionCredentials.refreshFromDisk()
        hasFullAccess = controller?.hasFullAccess == true
        isConfigured = CompanionCredentials.isConfigured
        if !CompanionCredentials.appGroupAvailable {
            statusLine = "SideStore muss die App Group für App und Tastatur behalten"
        } else if !hasFullAccess {
            statusLine = "Vollzugriff in Einstellungen aktivieren"
        } else if !isConfigured {
            statusLine = "NOCO AI App öffnen & mit PC koppeln"
        } else {
            statusLine = "Markiere Text oder tippe — dann Aktion wählen"
        }
    }

    func syncDocumentSnapshot() {
        guard let proxy = controller?.textDocumentProxy else { return }
        snapshotBefore = proxy.documentContextBeforeInput ?? ""
        snapshotSelected = proxy.selectedText ?? ""
    }

    var workingText: String {
        let selected = snapshotSelected.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selected.isEmpty { return selected }
        return snapshotBefore.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func insert(_ text: String) {
        controller?.textDocumentProxy.insertText(text)
        if shiftOn && !capsLock { shiftOn = false }
        syncDocumentSnapshot()
    }

    func deleteBackward() {
        controller?.textDocumentProxy.deleteBackward()
        syncDocumentSnapshot()
    }

    func returnKey() {
        insert("\n")
    }

    func space() {
        insert(" ")
    }

    func nextKeyboard() {
        controller?.advanceToNextInputMode()
    }

    func openSpeak() {
        controller?.openURL(URL(string: "nocoai://speak")!)
    }

    func openAppForSync() {
        controller?.openURL(URL(string: "nocoai://keyboard-sync")!)
    }

    func toggleShift() {
        if shiftOn && capsLock {
            shiftOn = false
            capsLock = false
        } else if shiftOn {
            capsLock = true
        } else {
            shiftOn = true
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func toggleNumbers() {
        showingNumbers.toggle()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func run(_ action: KeyboardAIAction) {
        syncDocumentSnapshot()
        let source = workingText
        guard !source.isEmpty else {
            statusLine = "Kein Text — tippe oder markiere etwas"
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        guard hasFullAccess else {
            statusLine = "Vollzugriff nötig für KI"
            return
        }
        guard isConfigured else {
            statusLine = "Zuerst in der NOCO AI App koppeln"
            return
        }
        guard !isProcessing else { return }

        isProcessing = true
        lastError = nil
        statusLine = "\(action.title)…"
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.75)

        let hadSelection = !(snapshotSelected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let deleteCount = hadSelection
            ? snapshotSelected.count
            : (snapshotBefore.hasSuffix(source) ? source.count : snapshotBefore.count)

        runTask?.cancel()
        runTask = Task {
            defer { isProcessing = false }
            do {
                var assembled = ""
                var startedInsert = false

                do {
                    for try await chunk in KeyboardAIClient.streamRewrite(action: action, text: source) {
                        if Task.isCancelled { return }
                        if !startedInsert {
                            clearCharacters(deleteCount)
                            startedInsert = true
                        }
                        controller?.textDocumentProxy.insertText(chunk)
                        assembled += chunk
                    }
                } catch {
                    if Task.isCancelled { return }
                    // Only fall back if nothing was written yet
                    if !startedInsert {
                        let result = try await KeyboardAIClient.rewrite(action: action, text: source)
                        clearCharacters(deleteCount)
                        startedInsert = true
                        controller?.textDocumentProxy.insertText(result)
                        assembled = result
                    } else {
                        throw error
                    }
                }

                if Task.isCancelled { return }
                let clean = assembled.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { throw KeyboardAIClient.ClientError.empty }
                statusLine = "Fertig · \(action.title)"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                syncDocumentSnapshot()
            } catch {
                if Task.isCancelled { return }
                lastError = error.localizedDescription
                statusLine = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func clearCharacters(_ count: Int) {
        guard let proxy = controller?.textDocumentProxy, count > 0 else { return }
        for _ in 0..<count {
            proxy.deleteBackward()
        }
    }
}
