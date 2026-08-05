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
    private let keyHaptic = UIImpactFeedbackGenerator(style: .light)
    private let selectHaptic = UISelectionFeedbackGenerator()
    private let notifyHaptic = UINotificationFeedbackGenerator()

    func bind(controller: KeyboardViewController) {
        self.controller = controller
        keyHaptic.prepare()
        selectHaptic.prepare()
        refreshAccess()
    }

    func refreshAccess() {
        CompanionCredentials.refreshFromDisk()
        hasFullAccess = controller?.hasFullAccess == true
        isConfigured = CompanionCredentials.isConfigured
        if !CompanionCredentials.appGroupAvailable {
            statusLine = "SideStore: App Group für App + Tastatur behalten"
        } else if !hasFullAccess {
            statusLine = "Vollzugriff in Einstellungen aktivieren"
        } else if !isConfigured {
            statusLine = "NOCO AI App öffnen & mit PC koppeln"
        } else {
            statusLine = "Text tippen/markieren → Aktion tippen"
        }
    }

    func syncDocumentSnapshot() {
        guard let proxy = controller?.textDocumentProxy else { return }
        snapshotBefore = proxy.documentContextBeforeInput ?? ""
        snapshotSelected = proxy.selectedText ?? ""
    }

    /// Selection first; else last paragraph / capped context for speed.
    var workingText: String {
        let selected = snapshotSelected.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selected.isEmpty { return selected }
        let before = snapshotBefore.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !before.isEmpty else { return "" }
        if before.count <= 600 { return before }
        if let range = before.range(of: "\n", options: .backwards) {
            let tail = String(before[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { return String(tail.suffix(600)) }
        }
        return String(before.suffix(600))
    }

    func insert(_ text: String) {
        controller?.textDocumentProxy.insertText(text)
        if shiftOn && !capsLock { shiftOn = false }
        keyHaptic.impactOccurred(intensity: 0.38)
        keyHaptic.prepare()
        syncDocumentSnapshot()
    }

    func deleteBackward() {
        controller?.textDocumentProxy.deleteBackward()
        keyHaptic.impactOccurred(intensity: 0.28)
        keyHaptic.prepare()
        syncDocumentSnapshot()
    }

    func returnKey() { insert("\n") }
    func space() { insert(" ") }

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
        selectHaptic.selectionChanged()
        selectHaptic.prepare()
    }

    func toggleNumbers() {
        showingNumbers.toggle()
        selectHaptic.selectionChanged()
        selectHaptic.prepare()
    }

    func run(_ action: KeyboardAIAction) {
        syncDocumentSnapshot()
        let source = workingText
        guard !source.isEmpty else {
            statusLine = "Kein Text — tippe oder markiere etwas"
            notifyHaptic.notificationOccurred(.warning)
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
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7)

        let hadSelection = !(snapshotSelected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let deleteCount = hadSelection
            ? snapshotSelected.count
            : (snapshotBefore.hasSuffix(source) ? source.count : min(source.count, snapshotBefore.count))

        runTask?.cancel()
        runTask = Task {
            defer { isProcessing = false }
            do {
                // One-shot flash: more reliable than streaming into the field
                let result = try await KeyboardAIClient.rewrite(action: action, text: source)
                if Task.isCancelled { return }
                clearCharacters(deleteCount)
                controller?.textDocumentProxy.insertText(result)
                statusLine = "Fertig · \(action.title)"
                notifyHaptic.notificationOccurred(.success)
                syncDocumentSnapshot()
            } catch {
                if Task.isCancelled { return }
                lastError = error.localizedDescription
                statusLine = error.localizedDescription
                notifyHaptic.notificationOccurred(.error)
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
