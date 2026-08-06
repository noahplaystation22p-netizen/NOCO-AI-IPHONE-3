import Foundation

/// User-defined keyboard AI shortcut (shown as a chip on the NOCO keyboard).
struct KeyboardCustomShortcut: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var systemImage: String
    /// What the AI should do with the marked/typed text.
    var prompt: String
    var createdAt: TimeInterval

    init(
        id: String = UUID().uuidString,
        name: String,
        systemImage: String = "sparkles",
        prompt: String,
        createdAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.name = name
        self.systemImage = systemImage
        self.prompt = prompt
        self.createdAt = createdAt
    }

    /// Full LLM message for the keyboard flash rewrite.
    func fullPrompt(for text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let injected: String
        if instruction.localizedCaseInsensitiveContains("{{text}}") {
            injected = instruction.replacingOccurrences(
                of: "{{text}}",
                with: t,
                options: .caseInsensitive
            )
        } else {
            injected = """
            \(instruction)

            TEXT:
            \(t)
            """
        }
        return """
        Du bist ein smarter Text-Assistent für Tastatur-Shortcuts.
        Führe die Anweisung am TEXT aus. Antworte AUSSCHLIESSLICH mit dem fertigen Ergebnis —
        kein Intro, kein „Gerne“, kein Markdown-Wrapper, keine Anführungszeichen um den ganzen Text.
        Wenn die Anweisung den Inhalt umformt (Tabelle, Liste, Großbuchstaben, Kommas entfernen …): tu genau das.
        Wenn der Text eine Frage ist und die Anweisung keine Antwort verlangt: nicht beantworten, nur umformen.

        ANWEISUNG:
        \(injected)
        """
    }

    func displayLabel(for text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let clip = t.count > 72 ? String(t.prefix(72)) + "…" : t
        return "\(name): \(clip)"
    }
}

/// One chip in the keyboard AI toolbar (built-in or custom).
enum KeyboardToolbarChip: Identifiable, Equatable {
    case builtin(KeyboardAIAction)
    case custom(KeyboardCustomShortcut)

    var id: String {
        switch self {
        case .builtin(let a): return "builtin:\(a.rawValue)"
        case .custom(let c): return "custom:\(c.id)"
        }
    }

    var title: String {
        switch self {
        case .builtin(let a): return a.title
        case .custom(let c): return c.name
        }
    }

    var systemImage: String {
        switch self {
        case .builtin(let a): return a.systemImage
        case .custom(let c): return c.systemImage
        }
    }

    var isPrimary: Bool {
        if case .builtin(let a) = self { return a.isPrimary }
        return false
    }

    var isAnswer: Bool {
        if case .builtin(let a) = self { return a.isAnswer }
        return false
    }

    var isComplete: Bool {
        if case .builtin(let a) = self { return a.isComplete }
        return false
    }

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }
}

/// Shared App Group prefs for keyboard chip order + custom shortcuts.
enum KeyboardChipPreferences {
    static let appGroupId = CompanionCredentials.appGroupId

    private static var suite: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }

    private static var diskURL: URL? {
        containerURL?.appendingPathComponent("keyboard-chips.json", isDirectory: false)
    }

    private enum Keys {
        static let order = "nocoai.kb.chipOrder"
        static let customs = "nocoai.kb.customShortcuts"
        static let kbOrder = "nocoai.kb.chipOrder.std"
        static let kbCustoms = "nocoai.kb.customShortcuts.std"
    }

    private struct DiskPayload: Codable {
        var order: [String]
        var customs: [KeyboardCustomShortcut]
        var updatedAt: TimeInterval?
    }

    // MARK: - Defaults

    static var defaultOrder: [String] {
        KeyboardAIAction.allCases.map(\.rawValue)
    }

    // MARK: - Order (builtin rawValues + "custom:<uuid>")

    static var chipOrder: [String] {
        get {
            if let arr = suite?.stringArray(forKey: Keys.order), !arr.isEmpty { return arr }
            if let disk = readDisk(), !disk.order.isEmpty { return disk.order }
            if let arr = UserDefaults.standard.stringArray(forKey: Keys.kbOrder), !arr.isEmpty { return arr }
            if let arr = UserDefaults.standard.stringArray(forKey: Keys.order), !arr.isEmpty { return arr }
            return defaultOrder
        }
        set {
            suite?.set(newValue, forKey: Keys.order)
            UserDefaults.standard.set(newValue, forKey: Keys.order)
            UserDefaults.standard.set(newValue, forKey: Keys.kbOrder)
            writeDisk()
        }
    }

    static var customShortcuts: [KeyboardCustomShortcut] {
        get {
            if let data = suite?.data(forKey: Keys.customs),
               let decoded = try? JSONDecoder().decode([KeyboardCustomShortcut].self, from: data) {
                return decoded
            }
            if let disk = readDisk() { return disk.customs }
            if let data = UserDefaults.standard.data(forKey: Keys.kbCustoms),
               let decoded = try? JSONDecoder().decode([KeyboardCustomShortcut].self, from: data) {
                return decoded
            }
            if let data = UserDefaults.standard.data(forKey: Keys.customs),
               let decoded = try? JSONDecoder().decode([KeyboardCustomShortcut].self, from: data) {
                return decoded
            }
            return []
        }
        set {
            let data = (try? JSONEncoder().encode(newValue)) ?? Data()
            suite?.set(data, forKey: Keys.customs)
            UserDefaults.standard.set(data, forKey: Keys.customs)
            UserDefaults.standard.set(data, forKey: Keys.kbCustoms)
            writeDisk()
        }
    }

    /// Chips shown on the keyboard toolbar (enabled order).
    static func resolvedChips() -> [KeyboardToolbarChip] {
        refreshFromDisk()
        let customs = Dictionary(uniqueKeysWithValues: customShortcuts.map { ($0.id, $0) })
        var seen = Set<String>()
        var out: [KeyboardToolbarChip] = []

        for token in chipOrder {
            if token.hasPrefix("custom:") {
                let id = String(token.dropFirst("custom:".count))
                if let c = customs[id], !seen.contains(token) {
                    out.append(.custom(c))
                    seen.insert(token)
                }
            } else if let action = KeyboardAIAction(rawValue: token) {
                let key = "builtin:\(action.rawValue)"
                if !seen.contains(key) {
                    out.append(.builtin(action))
                    seen.insert(key)
                }
            }
        }

        // Append new built-ins missing from older saved orders (e.g. Satz / Liste)
        for action in KeyboardAIAction.allCases {
            let key = "builtin:\(action.rawValue)"
            if !seen.contains(key) {
                let insertAfter: KeyboardAIAction? = {
                    switch action {
                    case .complete: return .improve
                    case .list: return .complete
                    default: return nil
                    }
                }()
                if let after = insertAfter,
                   let idx = out.firstIndex(where: {
                       if case .builtin(let a) = $0 { return a == after } else { return false }
                   }) {
                    out.insert(.builtin(action), at: idx + 1)
                } else {
                    out.append(.builtin(action))
                }
                seen.insert(key)
            }
        }

        // If order empty/broken, fall back to all built-ins
        if out.isEmpty {
            out = KeyboardAIAction.allCases.map { .builtin($0) }
        }
        return out
    }

    static func save(order: [String], customs: [KeyboardCustomShortcut]) {
        chipOrder = order
        customShortcuts = customs
    }

    static func addCustom(_ shortcut: KeyboardCustomShortcut) {
        var customs = customShortcuts
        customs.append(shortcut)
        customShortcuts = customs
        var order = chipOrder
        let token = "custom:\(shortcut.id)"
        if !order.contains(token) {
            order.append(token)
            chipOrder = order
        }
    }

    static func updateCustom(_ shortcut: KeyboardCustomShortcut) {
        var customs = customShortcuts
        if let idx = customs.firstIndex(where: { $0.id == shortcut.id }) {
            customs[idx] = shortcut
            customShortcuts = customs
        }
    }

    static func deleteCustom(id: String) {
        customShortcuts = customShortcuts.filter { $0.id != id }
        chipOrder = chipOrder.filter { $0 != "custom:\(id)" }
    }

    static func refreshFromDisk() {
        guard let disk = readDisk() else { return }
        if !disk.order.isEmpty {
            suite?.set(disk.order, forKey: Keys.order)
        }
        if let data = try? JSONEncoder().encode(disk.customs) {
            suite?.set(data, forKey: Keys.customs)
        }
    }

    /// Call after editing in the main app so the keyboard sees changes.
    static func pushToKeyboard() {
        writeDisk()
        // Touch suite so extension can pick up
        suite?.set(Date().timeIntervalSince1970, forKey: "nocoai.kb.chipsUpdatedAt")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "nocoai.kb.chipsUpdatedAt")
    }

    // MARK: - Disk

    private static func readDisk() -> DiskPayload? {
        guard let url = diskURL,
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(DiskPayload.self, from: data) else { return nil }
        return payload
    }

    private static func writeDisk() {
        guard let url = diskURL else { return }
        let payload = DiskPayload(
            order: chipOrder,
            customs: customShortcuts,
            updatedAt: Date().timeIntervalSince1970
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
