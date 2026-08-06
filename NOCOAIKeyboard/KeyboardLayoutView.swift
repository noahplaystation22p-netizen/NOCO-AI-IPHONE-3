import SwiftUI

/// German QWERTZ keyboard with Apple-style key popups + long-press accents.
struct KeyboardLayoutView: View {
    @ObservedObject var model: KeyboardViewModel
    @Environment(\.colorScheme) private var scheme

    private let row1 = Array("qwertzuiopü")
    private let row2 = Array("asdfghjklöä")
    private let row3 = Array("yxcvbnm")

    private let num1 = Array("1234567890")
    private let num2 = Array("-/:;()€&@\"")
    private let num3 = Array(".,?!ß'")

    var body: some View {
        VStack(spacing: 8) {
            if model.showingNumbers {
                numbersLayout
            } else {
                lettersLayout
            }
        }
        .padding(.horizontal, 3)
        .padding(.top, 4)
        .animation(.easeOut(duration: 0.15), value: model.showingNumbers)
    }

    private var lettersLayout: some View {
        VStack(spacing: 8) {
            letterRow(row1)
            letterRow(row2, sidePad: 4)
            HStack(spacing: 6) {
                ModifierKey(
                    symbol: model.capsLock ? "capslock.fill" : "shift.fill",
                    width: 44,
                    active: model.shiftOn || model.capsLock
                ) {
                    model.toggleShift()
                }
                letterRowContent(row3)
                DeleteKey(width: 44) {
                    model.beginDeleteHold()
                } onEnd: {
                    model.endDeleteHold()
                }
            }
            bottomRow(leftTitle: "123")
        }
    }

    private var numbersLayout: some View {
        VStack(spacing: 8) {
            letterRow(num1)
            letterRow(num2)
            HStack(spacing: 6) {
                ModifierKey(title: "#+=", width: 44) {
                    model.insert("#")
                }
                letterRowContent(num3)
                DeleteKey(width: 44) {
                    model.beginDeleteHold()
                } onEnd: {
                    model.endDeleteHold()
                }
            }
            bottomRow(leftTitle: "ABC")
        }
    }

    private func bottomRow(leftTitle: String) -> some View {
        HStack(spacing: 6) {
            ModifierKey(title: leftTitle, width: 44) {
                model.toggleNumbers()
            }
            // Period key — hold & scrub for comma and other punctuation (replaces language globe)
            PunctuationKey { inserted in
                model.insert(inserted)
            }
            SpaceKey {
                model.space()
            }
            ModifierKey(symbol: "bubble.left.fill", width: 44) {
                model.toggleAskPanel()
            }
            ModifierKey(title: "return", width: 70, prominent: true) {
                model.returnKey()
            }
        }
    }

    private func letterRow(_ chars: [Character], sidePad: CGFloat = 0) -> some View {
        HStack(spacing: 6) {
            if sidePad > 0 { Spacer(minLength: sidePad) }
            letterRowContent(chars)
            if sidePad > 0 { Spacer(minLength: sidePad) }
        }
    }

    private func letterRowContent(_ chars: [Character]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(chars.enumerated()), id: \.offset) { _, ch in
                let label = display(ch)
                LetterKey(
                    label: label,
                    accents: AccentMap.variants(for: label)
                ) { inserted in
                    model.insert(inserted)
                }
            }
        }
    }

    private func display(_ ch: Character) -> String {
        let s = String(ch)
        return (model.shiftOn || model.capsLock) ? s.uppercased() : s
    }
}

// MARK: - Accents (German + common)

enum AccentMap {
    static func variants(for label: String) -> [String] {
        guard let first = label.first else { return [] }
        let lower = String(first).lowercased()
        let upper = label == label.uppercased() && label != label.lowercased()
        let map: [String: String] = [
            "a": "aäàáâæãåā",
            "e": "eèéêëēėę",
            "i": "iìíîïīį",
            "o": "oöòóôõøōœ",
            "u": "uüùúûū",
            "s": "sßśš",
            "n": "nñń",
            "c": "cçćč",
            "y": "yÿý",
            "z": "zžźż",
            "ä": "äæ",
            "ö": "öøœ",
            "ü": "ü",
            "ß": "ßss"
        ]
        guard let chars = map[lower] else { return [] }
        let variants = chars.map { String($0) }
        if upper {
            return variants.map { $0.uppercased() }
        }
        return variants
    }
}

// MARK: - Letter key with popup + long-press accents

private struct LetterKey: View {
    let label: String
    let accents: [String]
    var onInsert: (String) -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var pressed = false
    @State private var showAccents = false
    @State private var accentIndex = 0
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        Text(label)
            .font(.system(size: 24, weight: .regular, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(keyFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.white.opacity(pressed ? 0.08 : 0.14), lineWidth: 0.5)
                    )
                    .shadow(
                        color: .black.opacity(0.35),
                        radius: pressed ? 0 : 0.5,
                        y: pressed ? 0 : 1
                    )
            )
            .overlay(alignment: .top) {
                if pressed {
                    popup
                        .offset(y: showAccents ? -62 : -58)
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .bottom)))
                        .zIndex(50)
                }
            }
            .zIndex(pressed ? 40 : 0)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged(handleChanged)
                    .onEnded(handleEnded)
            )
    }

    @ViewBuilder
    private var popup: some View {
        if showAccents, accents.count > 1 {
            HStack(spacing: 2) {
                ForEach(Array(accents.enumerated()), id: \.offset) { idx, ch in
                    Text(ch)
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .frame(width: 34, height: 44)
                        .foregroundStyle(idx == accentIndex ? Color.white : Color.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(idx == accentIndex
                                      ? Color(red: 0.28, green: 0.48, blue: 0.98)
                                      : Color.clear)
                        )
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(popupFill)
                    .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
            )
        } else {
            Text(label)
                .font(.system(size: 30, weight: .regular, design: .rounded))
                .frame(width: 52, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(popupFill)
                        .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
                )
        }
    }

    private var keyFill: Color {
        if pressed {
            return Color(red: 0.38, green: 0.40, blue: 0.46)
        }
        return Color(red: 0.28, green: 0.29, blue: 0.34)
    }

    private var popupFill: Color {
        scheme == .dark ? Color(white: 0.42) : .white
    }

    private func handleChanged(_ value: DragGesture.Value) {
        if !pressed {
            pressed = true
            accentIndex = 0
            showAccents = false
            holdTask?.cancel()
            holdTask = Task {
                try? await Task.sleep(nanoseconds: 380_000_000)
                guard !Task.isCancelled else { return }
                if accents.count > 1 {
                    showAccents = true
                    accentIndex = min(1, accents.count - 1) // first accent after base
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7)
                }
            }
        }
        if showAccents, accents.count > 1 {
            // Horizontal scrub across accent strip
            let x = value.translation.width
            let step: CGFloat = 34
            let raw = Int((x / step).rounded()) + 1
            let next = min(max(raw, 0), accents.count - 1)
            if next != accentIndex {
                accentIndex = next
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
    }

    private func handleEnded(_ value: DragGesture.Value) {
        holdTask?.cancel()
        holdTask = nil
        let insertChar: String
        if showAccents, accents.indices.contains(accentIndex) {
            insertChar = accents[accentIndex]
        } else {
            insertChar = label
        }
        pressed = false
        showAccents = false
        accentIndex = 0
        // Tiny movement still counts as tap
        onInsert(insertChar)
    }
}

// MARK: - Punctuation (tap = period, hold = comma / more)

/// Fixed-width `.` key with long-press scrub for `, ; : ! ? …` etc.
private struct PunctuationKey: View {
    var onInsert: (String) -> Void

    private let marks = [".", ",", ";", ":", "!", "?", "…", "—", "'", "\""]

    @Environment(\.colorScheme) private var scheme
    @State private var pressed = false
    @State private var showPicker = false
    @State private var pickIndex = 0
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        Text(".")
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .frame(width: 40, height: 46)
            .foregroundStyle(.white.opacity(0.95))
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(red: 0.18, green: 0.19, blue: 0.23))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
            .overlay(alignment: .top) {
                if pressed {
                    picker
                        .offset(y: showPicker ? -62 : -58)
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .bottom)))
                        .zIndex(50)
                }
            }
            .zIndex(pressed ? 40 : 0)
            .scaleEffect(pressed ? 0.96 : 1)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged(handleChanged)
                    .onEnded(handleEnded)
            )
    }

    @ViewBuilder
    private var picker: some View {
        if showPicker {
            HStack(spacing: 2) {
                ForEach(Array(marks.enumerated()), id: \.offset) { idx, ch in
                    Text(ch)
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .frame(width: 30, height: 42)
                        .foregroundStyle(idx == pickIndex ? Color.white : Color.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(idx == pickIndex
                                      ? Color(red: 0.28, green: 0.48, blue: 0.98)
                                      : Color.clear)
                        )
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(scheme == .dark ? Color(white: 0.42) : .white)
                    .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
            )
        } else {
            Text(".")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .frame(width: 48, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(scheme == .dark ? Color(white: 0.42) : .white)
                        .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
                )
        }
    }

    private func handleChanged(_ value: DragGesture.Value) {
        if !pressed {
            pressed = true
            pickIndex = 0
            showPicker = false
            holdTask?.cancel()
            holdTask = Task {
                try? await Task.sleep(nanoseconds: 320_000_000)
                guard !Task.isCancelled else { return }
                showPicker = true
                pickIndex = 1 // default highlight comma on hold
                UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7)
            }
        }
        if showPicker {
            let x = value.translation.width
            let step: CGFloat = 30
            let raw = Int((x / step).rounded()) + 1
            let next = min(max(raw, 0), marks.count - 1)
            if next != pickIndex {
                pickIndex = next
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
    }

    private func handleEnded(_ value: DragGesture.Value) {
        holdTask?.cancel()
        holdTask = nil
        let insertChar: String
        if showPicker, marks.indices.contains(pickIndex) {
            insertChar = marks[pickIndex]
        } else {
            insertChar = "."
        }
        pressed = false
        showPicker = false
        pickIndex = 0
        onInsert(insertChar)
    }
}

// MARK: - Modifier / Space

private struct DeleteKey: View {
    var width: CGFloat = 44
    var onBegin: () -> Void
    var onEnd: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var pressed = false

    var body: some View {
        Image(systemName: "delete.backward")
            .font(.system(size: 16, weight: .semibold))
            .frame(width: width, height: 46)
            .foregroundStyle(.white.opacity(0.9))
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(red: 0.18, green: 0.19, blue: 0.23))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
            .scaleEffect(pressed ? 0.96 : 1)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed {
                            pressed = true
                            onBegin()
                        }
                    }
                    .onEnded { _ in
                        pressed = false
                        onEnd()
                    }
            )
    }
}

private struct ModifierKey: View {
    var title: String? = nil
    var symbol: String? = nil
    var width: CGFloat = 44
    var active = false
    var prominent = false
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var pressed = false

    var body: some View {
        Group {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
            } else if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
        }
        .frame(width: width, height: 46)
        .foregroundStyle(prominent ? .white : .white.opacity(0.9))
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(
                            prominent
                            ? Color.white.opacity(0.22)
                            : (scheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.04)),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: .black.opacity(pressed ? 0 : 0.1), radius: 0.4, y: 1)
        )
        .scaleEffect(pressed ? 0.96 : 1)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed { pressed = true }
                }
                .onEnded { _ in
                    pressed = false
                    action()
                }
        )
    }

    private var fill: AnyShapeStyle {
        if prominent {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.34, green: 0.56, blue: 1.0),
                        Color(red: 0.4, green: 0.72, blue: 0.95)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        if active || pressed {
            return AnyShapeStyle(scheme == .dark ? Color.white.opacity(0.52) : Color.white)
        }
        return AnyShapeStyle(
            Color(red: 0.18, green: 0.19, blue: 0.23)
        )
    }
}

private struct SpaceKey: View {
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var pressed = false

    var body: some View {
        Text("Leertaste")
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(red: 0.26, green: 0.27, blue: 0.32).opacity(pressed ? 0.85 : 1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 0.4, y: 1)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !pressed { pressed = true } }
                    .onEnded { _ in
                        pressed = false
                        action()
                    }
            )
    }
}
