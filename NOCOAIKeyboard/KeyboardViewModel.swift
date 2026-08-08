import SwiftUI
import UIKit

@MainActor
final class KeyboardViewModel: ObservableObject {
    @Published var hasFullAccess = false
    @Published var isConfigured = false
    @Published var isProcessing = false
    @Published var statusLine = "NOCO AI bereit"
    @Published var shiftOn = false
    @Published var capsLock = false
    @Published var showingNumbers = false
    @Published var lastError: String?
    @Published var showIntelligenceBurst = false
    @Published var animationPhase: AnimationPhase = .idle
    @Published var overlayTitle = "…"
    @Published var toolbarChips: [KeyboardToolbarChip] = []
    @Published var showAskPanel = false
    @Published var askDraft = ""
    @Published var askReply = ""
    @Published var isAsking = false

    /// Compact rewrite actions shown only inside the NOCO AI panel.
    var quickAIActions: [KeyboardAIAction] {
        [.improve, .cleanup, .complete, .shorten, .answer]
    }

    // MARK: NOCO AI Diktat
    @Published var isDictating = false
    @Published var isDictationPolishing = false
    @Published var dictationLiveText = ""
    @Published var dictationLevel: CGFloat = 0
    @Published var dictationStyle: KeyboardDictationStyle = .current

    enum AnimationPhase: Equatable {
        case idle, thinking, writing, success
    }

    private var shortenStreak = 0
    private var lastShortenFingerprint = ""
    private var longerStreak = 0
    private var lastLongerFingerprint = ""

    private weak var controller: KeyboardViewController?
    private var snapshotBefore = ""
    private var snapshotSelected = ""
    private var runTask: Task<Void, Never>?
    private var deleteHoldTask: Task<Void, Never>?
    private var lastSpaceAt: Date?
    private let keyHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let selectHaptic = UISelectionFeedbackGenerator()
    private let notifyHaptic = UINotificationFeedbackGenerator()
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let voiceTyping = KeyboardVoiceTyping()
    private var dictationTickTask: Task<Void, Never>?
    private var dictationFinishing = false

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
        toolbarChips = []
        hasFullAccess = controller?.hasFullAccess == true
        isConfigured = CompanionCredentials.isConfigured
        dictationStyle = .current
        if !hasFullAccess {
            statusLine = "Vollzugriff in iPhone-Einstellungen aktivieren"
        } else if !isConfigured {
            statusLine = "In der App: Zugangsdaten aktualisieren"
        } else if showAskPanel {
            statusLine = "Tippe deine Frage — Return sendet"
        } else {
            statusLine = "NOCO AI bereit"
        }
    }

    func syncDocumentSnapshot() {
        guard let proxy = controller?.textDocumentProxy else { return }
        snapshotBefore = proxy.documentContextBeforeInput ?? ""
        snapshotSelected = proxy.selectedText ?? ""
    }

    /// Soft cap for unselected context (host apps often truncate anyway; selection = full text).
    private static let maxWorkingChars = 4500

    /// Selection first (best for long dictation); else as much before-cursor text as we can get.
    var workingText: String {
        let selected = snapshotSelected.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selected.isEmpty {
            return selected.count <= Self.maxWorkingChars
                ? selected
                : String(selected.suffix(Self.maxWorkingChars))
        }
        let before = snapshotBefore.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !before.isEmpty else { return "" }
        if before.count <= Self.maxWorkingChars { return before }
        // Prefer last paragraphs so the end of a long dictation isn't cut mid-thought
        if let range = before.range(of: "\n\n", options: .backwards) {
            let fromBreak = String(before[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if fromBreak.count >= 200 {
                return fromBreak.count <= Self.maxWorkingChars
                    ? fromBreak
                    : String(fromBreak.suffix(Self.maxWorkingChars))
            }
        }
        return String(before.suffix(Self.maxWorkingChars))
    }

    func insert(_ text: String) {
        // Ask panel captures typing — keyboard extensions can't reliably focus a TextField
        if showAskPanel {
            askDraft += text
            if shiftOn && !capsLock { shiftOn = false }
            keyHaptic.impactOccurred(intensity: 0.85)
            keyHaptic.prepare()
            return
        }
        controller?.textDocumentProxy.insertText(text)
        if shiftOn && !capsLock { shiftOn = false }
        keyHaptic.impactOccurred(intensity: 0.92)
        keyHaptic.prepare()
        syncDocumentSnapshot()
    }

    func deleteBackward() {
        if showAskPanel {
            if !askDraft.isEmpty {
                askDraft.removeLast()
                keyHaptic.impactOccurred(intensity: 0.7)
                keyHaptic.prepare()
            }
            return
        }
        controller?.textDocumentProxy.deleteBackward()
        keyHaptic.impactOccurred(intensity: 0.78)
        keyHaptic.prepare()
        syncDocumentSnapshot()
    }

    /// Start hold-to-delete: chars → words → wipe all before cursor.
    func beginDeleteHold() {
        deleteHoldTask?.cancel()
        deleteBackward()
        deleteHoldTask = Task { [weak self] in
            guard let self else { return }
            // Continuous chars
            try? await Task.sleep(nanoseconds: 320_000_000)
            var ticks = 0
            while !Task.isCancelled {
                ticks += 1
                if ticks > 28 {
                    // Long hold: wipe everything before the cursor
                    await MainActor.run { self.deleteAllBeforeCursor() }
                    break
                } else if ticks > 10 {
                    await MainActor.run { self.deleteWordBackward() }
                    try? await Task.sleep(nanoseconds: 70_000_000)
                } else {
                    await MainActor.run { self.deleteBackward() }
                    let delay = UInt64(max(45, 120 - ticks * 8)) * 1_000_000
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
    }

    func endDeleteHold() {
        deleteHoldTask?.cancel()
        deleteHoldTask = nil
    }

    func deleteWordBackward() {
        if showAskPanel {
            while let last = askDraft.last, last.isWhitespace { askDraft.removeLast() }
            while let last = askDraft.last, !last.isWhitespace { askDraft.removeLast() }
            heavyHaptic.impactOccurred(intensity: 0.65)
            return
        }
        guard let proxy = controller?.textDocumentProxy else { return }
        let before = proxy.documentContextBeforeInput ?? ""
        guard !before.isEmpty else { return }
        var count = 0
        var sawContent = false
        for ch in before.reversed() {
            if ch.isWhitespace || ch.isNewline {
                if sawContent { break }
                count += 1
            } else {
                sawContent = true
                count += 1
            }
        }
        for _ in 0..<max(1, count) {
            proxy.deleteBackward()
        }
        heavyHaptic.impactOccurred(intensity: 0.7)
        heavyHaptic.prepare()
        syncDocumentSnapshot()
    }

    func deleteAllBeforeCursor() {
        if showAskPanel {
            askDraft = ""
            notifyHaptic.notificationOccurred(.warning)
            statusLine = "Frage gelöscht"
            return
        }
        guard let proxy = controller?.textDocumentProxy else { return }
        let before = proxy.documentContextBeforeInput ?? ""
        guard !before.isEmpty else { return }
        for _ in 0..<before.count {
            proxy.deleteBackward()
        }
        notifyHaptic.notificationOccurred(.warning)
        syncDocumentSnapshot()
        statusLine = "Alles gelöscht"
    }

    func returnKey() {
        if showAskPanel {
            if !askDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sendAsk()
            } else {
                insert("\n")
            }
            return
        }
        insert("\n")
    }

    /// Double-tap space → period + space (iOS-style).
    func space() {
        if showAskPanel {
            insert(" ")
            return
        }
        let now = Date()
        if let last = lastSpaceAt, now.timeIntervalSince(last) < 0.35 {
            lastSpaceAt = nil
            // Replace the previous space with ". "
            controller?.textDocumentProxy.deleteBackward()
            insert(". ")
            selectHaptic.selectionChanged()
            return
        }
        lastSpaceAt = now
        insert(" ")
    }

    /// Apple-style cursor scrub via long-press space + drag.
    func moveCursor(by offset: Int) {
        guard offset != 0 else { return }
        if showAskPanel { return }
        controller?.textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
        selectHaptic.selectionChanged()
    }

    /// Opens the compact NOCO AI field and focuses typing into it (blinking cursor).
    func openNOCOAI() {
        if showAskPanel {
            closeNOCOAI()
            return
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            showAskPanel = true
        }
        askReply = ""
        statusLine = "Tippe deine Frage — Return sendet"
        selectHaptic.selectionChanged()
        controller?.updateKeyboardHeight()
    }

    func closeNOCOAI() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            showAskPanel = false
        }
        statusLine = "NOCO AI bereit"
        controller?.updateKeyboardHeight()
    }

    func toggleAskPanel() {
        openNOCOAI()
    }

    func runBuiltinAction(_ action: KeyboardAIAction) {
        runChip(.builtin(action))
    }

    func sendAsk() {
        let q = askDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        guard hasFullAccess, isConfigured else {
            statusLine = hasFullAccess ? "Zuerst in der App koppeln" : "Vollzugriff nötig"
            notifyHaptic.notificationOccurred(.warning)
            return
        }
        guard !isAsking, !isProcessing else { return }
        isAsking = true
        askReply = ""
        showIntelligenceBurst = true
        animationPhase = .thinking
        overlayTitle = "Frage…"
        statusLine = "NOCO denkt…"
        heavyHaptic.impactOccurred(intensity: 1.0)

        runTask?.cancel()
        runTask = Task {
            defer { isAsking = false }
            do {
                let reply = try await KeyboardAIClient.ask(question: q)
                if Task.isCancelled { return }
                animationPhase = .success
                // Keep the full answer visible — don't over-sanitize Q&A replies.
                askReply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                statusLine = "Antwort bereit"
                notifyHaptic.notificationOccurred(.success)
                controller?.updateKeyboardHeight()
                try? await Task.sleep(nanoseconds: 280_000_000)
                withAnimation(.easeOut(duration: 0.22)) {
                    showIntelligenceBurst = false
                    animationPhase = .idle
                }
            } catch {
                if Task.isCancelled { return }
                showIntelligenceBurst = false
                animationPhase = .idle
                askReply = ""
                statusLine = error.localizedDescription
                notifyHaptic.notificationOccurred(.error)
            }
        }
    }

    func insertAskReply() {
        let text = askReply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Always insert into the host field, not the Ask draft
        controller?.textDocumentProxy.insertText(text)
        statusLine = "Eingefügt"
        notifyHaptic.notificationOccurred(.success)
        syncDocumentSnapshot()
    }

    func clearAskDraft() {
        askDraft = ""
        askReply = ""
        statusLine = "Tippe deine Frage auf der Tastatur"
        controller?.updateKeyboardHeight()
    }

    func nextKeyboard() {
        controller?.advanceToNextInputMode()
    }

    func openSpeak() {
        guard hasFullAccess else {
            statusLine = "Vollzugriff nötig für Voice AI"
            notifyHaptic.notificationOccurred(.warning)
            return
        }
        statusLine = "Voice AI startet…"
        selectHaptic.selectionChanged()
        // Open host app Voice AI via deep link (toggle)
        controller?.openURL(URL(string: "nocoai://speak")!)
    }

    /// Cycle Schnell → Intelligent → Professionell.
    func cycleDictationStyle() {
        dictationStyle = dictationStyle.next()
        KeyboardDictationStyle.current = dictationStyle
        statusLine = "Diktat: \(dictationStyle.title) — \(dictationStyle.subtitle)"
        selectHaptic.selectionChanged()
    }

    /// Toggle NOCO AI Voice Typing: speak → instant text → KI polish.
    func toggleDictation() {
        if isDictating {
            finishDictation()
            return
        }
        guard hasFullAccess else {
            statusLine = "Vollzugriff nötig für Diktat"
            notifyHaptic.notificationOccurred(.warning)
            return
        }
        guard !isProcessing, !isAsking, !isDictationPolishing else { return }

        runTask?.cancel()
        Task { @MainActor in
            if !voiceTyping.hasPermission {
                let ok = await voiceTyping.requestPermissions()
                guard ok else {
                    statusLine = voiceTyping.lastError ?? "Mikrofon / Spracherkennung erlauben"
                    notifyHaptic.notificationOccurred(.warning)
                    return
                }
            }
            do {
                try voiceTyping.start { [weak self] in
                    self?.finishDictation()
                }
                isDictating = true
                dictationLiveText = ""
                statusLine = "Sprich jetzt… (\(dictationStyle.title))"
                heavyHaptic.impactOccurred(intensity: 0.85)
                startDictationTicker()
            } catch {
                statusLine = error.localizedDescription
                notifyHaptic.notificationOccurred(.error)
            }
        }
    }

    private func startDictationTicker() {
        dictationTickTask?.cancel()
        dictationTickTask = Task { @MainActor in
            while !Task.isCancelled, isDictating {
                dictationLiveText = voiceTyping.liveTranscript
                dictationLevel = voiceTyping.level
                if !dictationLiveText.isEmpty {
                    statusLine = dictationLiveText
                }
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
    }

    private func finishDictation() {
        guard !dictationFinishing else { return }
        guard isDictating else { return }
        dictationFinishing = true
        defer { dictationFinishing = false }

        dictationTickTask?.cancel()
        dictationTickTask = nil
        let raw = voiceTyping.stop(cancel: false)
        isDictating = false
        dictationLevel = 0
        guard !raw.isEmpty else {
            statusLine = "Nichts gehört — nochmal tippen"
            notifyHaptic.notificationOccurred(.warning)
            return
        }

        // Instant: show spoken text immediately, then polish in background.
        if showAskPanel {
            askDraft += (askDraft.isEmpty ? "" : " ") + raw
            statusLine = "Diktat im Fragefeld"
            notifyHaptic.notificationOccurred(.success)
            return
        }

        controller?.textDocumentProxy.insertText(raw)
        syncDocumentSnapshot()

        guard isConfigured else {
            statusLine = "Text übernommen — App koppeln für KI-Politur"
            notifyHaptic.notificationOccurred(.success)
            return
        }

        statusLine = "KI formt Text…"
        isDictationPolishing = true
        isProcessing = true
        showIntelligenceBurst = true
        animationPhase = .thinking
        overlayTitle = "NOCO AI Diktat…"
        selectHaptic.selectionChanged()

        let style = dictationStyle
        let inserted = raw
        runTask?.cancel()
        runTask = Task { @MainActor in
            defer {
                isDictationPolishing = false
                isProcessing = false
            }
            do {
                let polished = try await KeyboardAIClient.rewrite(
                    action: style.polishAction,
                    text: inserted
                )
                if Task.isCancelled { return }
                let final = polished.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !final.isEmpty, final != inserted else {
                    animationPhase = .success
                    overlayTitle = ""
                    statusLine = "Fertig"
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    withAnimation(.easeOut(duration: 0.28)) {
                        showIntelligenceBurst = false
                        animationPhase = .idle
                    }
                    return
                }
                animationPhase = .writing
                overlayTitle = ""
                clearCharacters(inserted.count)
                await typewriterInsert(final)
                animationPhase = .success
                statusLine = "Fertig · \(style.title)"
                notifyHaptic.notificationOccurred(.success)
                syncDocumentSnapshot()
                try? await Task.sleep(nanoseconds: 420_000_000)
                withAnimation(.easeOut(duration: 0.28)) {
                    showIntelligenceBurst = false
                    animationPhase = .idle
                }
            } catch {
                if Task.isCancelled { return }
                showIntelligenceBurst = false
                animationPhase = .idle
                statusLine = "Text übernommen (KI kurz offline)"
                notifyHaptic.notificationOccurred(.warning)
            }
        }
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
                    var level = 1
                    if action == .shorten {
                        let fp = source
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased()
                        if fp == lastShortenFingerprint ||
                            (!lastShortenFingerprint.isEmpty && fp.hasPrefix(String(lastShortenFingerprint.prefix(min(40, lastShortenFingerprint.count))))) {
                            shortenStreak = min(shortenStreak + 1, 4)
                        } else {
                            shortenStreak = 1
                        }
                        level = shortenStreak
                        overlayTitle = level == 1
                            ? "Kürzer…"
                            : "Kürzer (\(level)/4)…"
                        statusLine = overlayTitle
                    } else if action == .longer {
                        let fp = source
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased()
                        if fp == lastLongerFingerprint ||
                            (!lastLongerFingerprint.isEmpty && lastLongerFingerprint.hasPrefix(String(fp.prefix(min(40, fp.count))))) {
                            longerStreak = min(longerStreak + 1, 4)
                        } else {
                            longerStreak = 1
                        }
                        level = longerStreak
                        overlayTitle = level == 1
                            ? "Länger…"
                            : "Länger (\(level)/4)…"
                        statusLine = overlayTitle
                    }
                    result = try await KeyboardAIClient.rewrite(action: action, text: source, shortenLevel: level)
                    if action == .shorten {
                        lastShortenFingerprint = result
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased()
                    } else if action == .longer {
                        lastLongerFingerprint = result
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased()
                    }
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
