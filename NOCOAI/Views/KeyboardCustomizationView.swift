import SwiftUI

/// Customize NOCO keyboard AI chips: reorder built-ins + create smart prompt shortcuts.
struct KeyboardCustomizationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var order: [String] = KeyboardChipPreferences.chipOrder
    @State private var customs: [KeyboardCustomShortcut] = KeyboardChipPreferences.customShortcuts
    @State private var showEditor = false
    @State private var editing: KeyboardCustomShortcut?
    @State private var savedFlash = false

    private let iconChoices = [
        "sparkles", "wand.and.stars", "textformat", "list.bullet",
        "tablecells", "character", "scissors", "paintbrush",
        "bolt.fill", "star.fill", "highlighter", "quote.bubble"
    ]

    var body: some View {
        List {
            Section {
                Text("Ziehen zum Sortieren. Eigene Shortcuts = dein Prompt + Name auf der Tastatur.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            Section("Reihenfolge auf der Tastatur") {
                ForEach(order, id: \.self) { token in
                    chipRow(for: token)
                }
                .onMove(perform: move)
                .onDelete(perform: deleteFromOrder)
            }

            Section {
                Button {
                    editing = KeyboardCustomShortcut(
                        name: "Mein Shortcut",
                        systemImage: "sparkles",
                        prompt: "Verbessere den folgenden Text: korrigiere Rechtschreibung und entferne alle Kommas."
                    )
                    showEditor = true
                } label: {
                    Label("Neuen Shortcut erstellen", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Eigene KI-Shortcuts")
            } footer: {
                Text("Beispiel-Prompts: „Alles in Großbuchstaben“, „Als Aufzählung“, „Als Markdown-Tabelle“, „Kommas entfernen“, „Formeller umschreiben“.")
            }

            if !customs.isEmpty {
                Section("Deine Shortcuts") {
                    ForEach(customs) { item in
                        Button {
                            editing = item
                            showEditor = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.systemImage)
                                    .foregroundStyle(NOCOAITheme.accent)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(item.prompt)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                deleteCustom(id: item.id)
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    save()
                } label: {
                    Label(savedFlash ? "Gespeichert ✓" : "Für Tastatur speichern", systemImage: "checkmark.circle.fill")
                }
                .disabled(savedFlash)
            } footer: {
                Text("Danach ggf. Tastatur kurz wechseln (Globus), damit die Chips neu laden. Vollzugriff muss an sein.")
            }
        }
        .navigationTitle("Tastatur anpassen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .sheet(isPresented: $showEditor) {
            if let editing {
                ShortcutEditorSheet(
                    shortcut: editing,
                    iconChoices: iconChoices,
                    onSave: { saved in
                        upsertCustom(saved)
                        showEditor = false
                        self.editing = nil
                        HapticService.success()
                    },
                    onCancel: {
                        showEditor = false
                        self.editing = nil
                    }
                )
            }
        }
        .onAppear {
            order = KeyboardChipPreferences.chipOrder
            customs = KeyboardChipPreferences.customShortcuts
            // Ensure all builtins present once
            ensureBuiltinsInOrder()
        }
    }

    @ViewBuilder
    private func chipRow(for token: String) -> some View {
        if token.hasPrefix("custom:") {
            let id = String(token.dropFirst("custom:".count))
            if let c = customs.first(where: { $0.id == id }) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name)
                        Text("Eigener Shortcut")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: c.systemImage)
                        .foregroundStyle(NOCOAITheme.accent)
                }
            } else {
                Text("Entfernter Shortcut")
                    .foregroundStyle(.secondary)
            }
        } else if let action = KeyboardAIAction(rawValue: token) {
            Label(action.title, systemImage: action.systemImage)
        } else {
            Text(token).foregroundStyle(.secondary)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
        HapticService.selection()
        savedFlash = false
    }

    private func deleteFromOrder(at offsets: IndexSet) {
        for index in offsets {
            let token = order[index]
            if token.hasPrefix("custom:") {
                let id = String(token.dropFirst("custom:".count))
                customs.removeAll { $0.id == id }
            }
        }
        order.remove(atOffsets: offsets)
        savedFlash = false
        HapticService.soft()
    }

    private func deleteCustom(id: String) {
        customs.removeAll { $0.id == id }
        order.removeAll { $0 == "custom:\(id)" }
        savedFlash = false
        HapticService.soft()
    }

    private func upsertCustom(_ shortcut: KeyboardCustomShortcut) {
        if let idx = customs.firstIndex(where: { $0.id == shortcut.id }) {
            customs[idx] = shortcut
        } else {
            customs.append(shortcut)
            let token = "custom:\(shortcut.id)"
            if !order.contains(token) {
                order.append(token)
            }
        }
        savedFlash = false
    }

    private func ensureBuiltinsInOrder() {
        var next = order
        for id in KeyboardChipPreferences.defaultOrder where !next.contains(id) {
            next.append(id)
        }
        // Drop unknown custom tokens without matching shortcut
        let customIds = Set(customs.map(\.id))
        next = next.filter { token in
            if token.hasPrefix("custom:") {
                return customIds.contains(String(token.dropFirst("custom:".count)))
            }
            return KeyboardAIAction(rawValue: token) != nil
        }
        order = next
    }

    private func save() {
        ensureBuiltinsInOrder()
        KeyboardChipPreferences.save(order: order, customs: customs)
        KeyboardChipPreferences.pushToKeyboard()
        // Also refresh credentials bridge so SideStore keyboards pick up disk files
        CompanionCredentials.refreshFromDisk()
        HapticService.success()
        withAnimation {
            savedFlash = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            savedFlash = false
        }
    }
}

// MARK: - Editor

private struct ShortcutEditorSheet: View {
    @State var shortcut: KeyboardCustomShortcut
    let iconChoices: [String]
    var onSave: (KeyboardCustomShortcut) -> Void
    var onCancel: () -> Void

    @FocusState private var focusPrompt: Bool

    private let examples = [
        "Mache alles in Großbuchstaben.",
        "Entferne alle Kommas und verbessere die Rechtschreibung.",
        "Formuliere als kurze Aufzählung mit Bindestrichen.",
        "Wandle in eine Markdown-Tabelle um.",
        "Schreibe den Text formeller und klarer, gleiche Länge."
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name auf der Tastatur") {
                    TextField("z. B. Großbuchstaben", text: $shortcut.name)
                }

                Section("Symbol") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(iconChoices, id: \.self) { icon in
                            Button {
                                shortcut.systemImage = icon
                                HapticService.selection()
                            } label: {
                                Image(systemName: icon)
                                    .font(.title3)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(shortcut.systemImage == icon
                                                  ? NOCOAITheme.accent.opacity(0.2)
                                                  : Color.primary.opacity(0.05))
                                    )
                                    .foregroundStyle(shortcut.systemImage == icon ? NOCOAITheme.accent : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    TextField("Was soll die KI mit dem Text machen?", text: $shortcut.prompt, axis: .vertical)
                        .lineLimit(4...10)
                        .focused($focusPrompt)
                } header: {
                    Text("Prompt / Anweisung")
                } footer: {
                    Text("Optional {{text}} einfügen — sonst wird dein markierter Text automatisch angehängt.")
                }

                Section("Beispiele tippen") {
                    ForEach(examples, id: \.self) { tip in
                        Button {
                            shortcut.prompt = tip
                            if shortcut.name == "Mein Shortcut" || shortcut.name.isEmpty {
                                shortcut.name = String(tip.prefix(22))
                            }
                            HapticService.selection()
                        } label: {
                            Text(tip)
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Shortcut")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        let name = shortcut.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let prompt = shortcut.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty, !prompt.isEmpty else { return }
                        shortcut.name = name
                        shortcut.prompt = prompt
                        onSave(shortcut)
                    }
                    .disabled(
                        shortcut.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        shortcut.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
            .onAppear { focusPrompt = true }
        }
    }
}
