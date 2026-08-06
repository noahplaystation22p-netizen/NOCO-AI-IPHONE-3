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
    @Published var showIntelligenceBurst = false
    @Published var animationPhase: AnimationPhase = .idle
    @Published var overlayTitle = "…"
    @Published var toolbarChips: [KeyboardToolbarChip] = KeyboardChipPreferences.resolvedChips()

    enum AnimationPhase: Equatable {
        case idle, thinking, writing, success
    }

    private weak var controller: KeyboardViewController?
    private var snapshotBefore = ""
    private var snapshotSelected = ""
    private var runTask: Task<Void, Never>?
    private let keyHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let selectHaptic = UISelectionFeedbackGenerator()
    private let notifyHaptic = UINotificationFeedbackGenerator()
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)

    func bind(controller: KeyboardViewController) {
        self.controller = controller
        keyHaptic.prepare()
        selectHaptic.prepare()
        heavyHaptic.prepare()
        refreshAccess()
    }

    func refreshAccess() {
        CompanionCredentials.refreshFromDisk()
        KeyboardChipPreferences.refreshFromDisk()
        toolbarChips = KeyboardChipPreferences.resolvedChips()
        hasFullAccess = controller?.hasFullAccess == true
        isConfigured = CompanionCredentials.isConfigured
        if !hasFullAccess {
            statusLine = "Vollzugriff in iPhone-Einstellungen aktivieren"
        } else if !isConfigured {
            statusLine = "In der App: Zugangsdaten aktualisieren"
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
        keyHaptic.impactOccurred(intensity: 0.92)
        keyHaptic.prepare()
        syncDocumentSnapshot()
    }

    func deleteBackward() {
        controller?.textDocumentProxy.deleteBackward()
        keyHaptic.impactOccurred(intensity: 0.78)
        keyHaptic.prepare()
        syncDocumentSnapshot()
    }

    func returnKey() { insert("\n") }
    func space() { insert(" ") }

    func nextKeyboard() {
        controller?.advanceToNextInputMode()
    }

    func openSpeak() {
        guard hasFullAccess else {
            statusLine = "Vollzugriff nötig für Speak"
            notifyHaptic.notificationOccurred(.warning)
            return
        }
        statusLine = "Speak startet…"
        selectHaptic.selectionChanged()
        // Open host app Speak (Sprachmodus) via deep link
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
        runChip(.builtin(action))
    }

    func runChip(_ chip: KeyboardToolbarChip) {
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
        showIntelligenceBurst = true
        animationPhase = .thinking
        overlayTitle = "\(chip.title)…"
        lastError = nil
        statusLine = "\(chip.title)…"
        heavyHaptic.impactOccurred(intensity: 1.0)
        heavyHaptic.prepare()
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.9)

        let hadSelection = !(snapshotSelected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let deleteCount = hadSelection
            ? snapshotSelected.count
            : (snapshotBefore.hasSuffix(source) ? source.count : min(source.count, snapshotBefore.count))

        runTask?.cancel()
        runTask = Task {
            defer {
                isProcessing = false
            }
            do {
                let result: String
                switch chip {
                case .builtin(let action):
                    result = try await KeyboardAIClient.rewrite(action: action, text: source)
                case .custom(let shortcut):
                    result = try await KeyboardAIClient.rewriteCustom(shortcut: shortcut, text: source)
                }
                if Task.isCancelled { return }
                animationPhase = .writing
                overlayTitle = ""
                statusLine = chip.title
                clearCharacters(deleteCount)
                await typewriterInsert(result)
                if Task.isCancelled { return }
                animationPhase = .success
                overlayTitle = ""
                statusLine = "Fertig"
                notifyHaptic.notificationOccurred(.success)
                syncDocumentSnapshot()
                try? await Task.sleep(nanoseconds: 480_000_000)
                withAnimation(.easeOut(duration: 0.3)) {
                    showIntelligenceBurst = false
                    animationPhase = .idle
                }
            } catch {
                if Task.isCancelled { return }
                showIntelligenceBurst = false
                animationPhase = .idle
                lastError = error.localizedDescription
                statusLine = error.localizedDescription
                notifyHaptic.notificationOccurred(.error)
            }
        }
    }

    private func typewriterInsert(_ text: String) async {
        guard let proxy = controller?.textDocumentProxy else { return }
        // Chunk insert for fluid Apple-like reveal without feeling sluggish
        let chars = Array(text)
        var i = 0
        let chunk = max(2, min(8, chars.count / 40 + 2))
        while i < chars.count {
            if Task.isCancelled { return }
            let end = min(i + chunk, chars.count)
            proxy.insertText(String(chars[i..<end]))
            i = end
            try? await Task.sleep(nanoseconds: 12_000_000)
        }
    }

    private func clearCharacters(_ count: Int) {
        guard let proxy = controller?.textDocumentProxy, count > 0 else { return }
        for _ in 0..<count {
            proxy.deleteBackward()
        }
    }
}
