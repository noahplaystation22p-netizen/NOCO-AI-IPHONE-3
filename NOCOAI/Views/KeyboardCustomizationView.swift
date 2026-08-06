import SwiftUI

/// Customize NOCO keyboard AI chips: reorder built-ins + create smart prompt shortcuts.
struct KeyboardCustomizationView: View {
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
                previewStrip
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: scheme == .dark
                                    ? [
                                        Color(red: 0.1, green: 0.12, blue: 0.18),
                                        Color(red: 0.08, green: 0.1, blue: 0.14)
                                    ]
                                    : [
                                        Color(red: 0.92, green: 0.94, blue: 0.99),
                                        Color(red: 0.88, green: 0.92, blue: 0.96)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            } header: {
                Text("Vorschau")
            } footer: {
                Text("So erscheinen deine Chips auf der Tastatur. Tippe „Bearbeiten“ zum Sortieren.")
            }

            Section {
                ForEach(order, id: \.self) { token in
                    chipRow(for: token)
                }
                .onMove(perform: move)
                .onDelete(perform: deleteFromOrder)
            } header: {
                Text("Auf der Tastatur")
            } footer: {
                Text("Wischen zum Entfernen · Bearbeiten zum Sortieren. Entfernte Chips bleiben unten verfügbar.")
            }

            if !availableBuiltinTokens.isEmpty || !availableCustomItems.isEmpty {
                Section {
                    ForEach(availableBuiltinTokens, id: \.self) { token in
                        if let action = KeyboardAIAction(rawValue: token) {
                            Button {
                                addToken(token)
                            } label: {
                                Label {
                                    HStack {
                                        Text(action.title)
                                        Spacer()
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundStyle(NOCOAITheme.accent)
                                    }
                                } icon: {
                                    Image(systemName: action.systemImage)
                                }
                            }
                        }
                    }
                    ForEach(availableCustomItems) { item in
                        Button {
                            addToken("custom:\(item.id)")
                        } label: {
                            Label {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                        Text("Eigener Shortcut")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(NOCOAITheme.accent)
                                }
                            } icon: {
                                Image(systemName: item.systemImage)
                            }
                        }
                    }
                } header: {
                    Text("Verfügbar — tippen zum Hinzufügen")
                } footer: {
                    Text("Hier landen entfernte Chips. Tippen fügt sie wieder auf die Tastatur.")
                }
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
                        .font(.body.weight(.semibold))
                        .foregroundStyle(NOCOAITheme.accent)
                }
            } header: {
                Text("Eigene KI-Shortcuts")
            } footer: {
                Text("Name + Prompt. Tippen auf der Tastatur führt die Anweisung am markierten Text aus.")
            }

            if !customs.isEmpty {
                Section {
                    ForEach(customs) { item in
                        Button {
                            editing = item
                            showEditor = true
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(NOCOAITheme.accent.opacity(0.14))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: item.systemImage)
                                        .foregroundStyle(NOCOAITheme.accent)
                                }
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
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                deleteCustomPermanently(id: item.id)
                            } label: {
                                Label("Endgültig löschen", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Deine Shortcuts verwalten")
                } footer: {
                    Text("„Endgültig löschen“ entfernt den Shortcut komplett. Zum nur Ausblenden: in „Auf der Tastatur“ wischen.")
                }
            }

            Section {
                Button {
                    save()
                } label: {
                    HStack {
                        Spacer()
                        Label(
                            savedFlash ? "Gespeichert" : "Für Tastatur speichern",
                            systemImage: savedFlash ? "checkmark.circle.fill" : "arrow.down.circle.fill"
                        )
                        .font(.body.weight(.semibold))
                        Spacer()
                    }
                }
                .disabled(savedFlash)
                .tint(savedFlash ? NOCOAITheme.success : NOCOAITheme.accent)
            } footer: {
                Text("Speichern schreibt in die App-Group — bleibt auch, wenn du die Tastatur entfernst und neu hinzufügst. Danach Tastatur einmal wechseln (Globus), damit Chips neu laden.")
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
            sanitizeOrder()
        }
    }

    private var availableBuiltinTokens: [String] {
        KeyboardChipPreferences.availableBuiltinTokens(order: order)
    }

    private var availableCustomItems: [KeyboardCustomShortcut] {
        KeyboardChipPreferences.availableCustoms(order: order, customs: customs)
    }

    private var previewStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(NOCOAITheme.accent)
                Text("NOCO AI")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.6)
                Spacer()
                Text("\(order.count) Chips")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(order, id: \.self) { token in
                        previewChip(for: token)
                    }
                }
            }
        }
    }

    private func previewChip(for token: String) -> some View {
        let meta = chipMeta(for: token)
        return HStack(spacing: 4) {
            Image(systemName: meta.icon)
                .font(.system(size: 10, weight: .semibold))
            Text(meta.title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .foregroundStyle(meta.primary ? .white : .primary)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    meta.primary
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.34, green: 0.56, blue: 1.0),
                                Color(red: 0.42, green: 0.78, blue: 0.95)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    : AnyShapeStyle(Color.primary.opacity(scheme == .dark ? 0.12 : 0.08))
                )
        )
    }

    private func chipMeta(for token: String) -> (title: String, icon: String, primary: Bool) {
        if token.hasPrefix("custom:") {
            let id = String(token.dropFirst("custom:".count))
            let c = customs.first(where: { $0.id == id })
            return (c?.name ?? "?", c?.systemImage ?? "sparkles", false)
        }
        if let action = KeyboardAIAction(rawValue: token) {
            return (action.title, action.systemImage, action.isPrimary)
        }
        return (token, "questionmark", false)
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
        // Only remove from toolbar — builtins stay available; customs stay until permanently deleted
        order.remove(atOffsets: offsets)
        savedFlash = false
        HapticService.soft()
    }

    private func addToken(_ token: String) {
        guard !order.contains(token) else { return }
        order.append(token)
        savedFlash = false
        HapticService.selection()
    }

    private func deleteCustomPermanently(id: String) {
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

    /// Drop invalid tokens only — never force-readd removed chips.
    private func sanitizeOrder() {
        let customIds = Set(customs.map(\.id))
        order = order.filter { token in
            if token.hasPrefix("custom:") {
                return customIds.contains(String(token.dropFirst("custom:".count)))
            }
            return KeyboardAIAction(rawValue: token) != nil
        }
        if order.isEmpty {
            order = KeyboardChipPreferences.defaultOrder
        }
    }

    private func save() {
        sanitizeOrder()
        KeyboardChipPreferences.save(order: order, customs: customs)
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
                Section {
                    TextField("z. B. Großbuchstaben", text: $shortcut.name)
                } header: {
                    Text("Name auf der Tastatur")
                } footer: {
                    Text("Kurz halten — erscheint als Chip über den Tasten.")
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
                                .multilineTextAlignment(.leading)
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
