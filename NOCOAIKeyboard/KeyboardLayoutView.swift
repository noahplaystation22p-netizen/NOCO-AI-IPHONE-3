import SwiftUI

/// Geometry matched to Apple’s system keyboard (measured portrait baselines:
/// iPhone SE/5: ~39pt keys, iPhone 6/13mini class 375pt: ~43pt, Plus/Max ≥414: ~46pt;
/// side margin 3–4, inter-key gap 6; German QWERTZ uses 11 equal columns).
private struct AppleKeyboardMetrics {
    let boardWidth: CGFloat

    /// Horizontal inset from screen edge to first/last key (Apple: 3 @ ≤399, 4 @ ≥400).
    var sideMargin: CGFloat { boardWidth >= 400 ? 4 : 3 }
    /// Gap between adjacent key faces (Apple portrait: 6).
    var keyGap: CGFloat { 6 }
    /// Vertical gap between rows (Apple ≈ keyGap − a little).
    var rowGap: CGFloat { 11 }
    /// Top padding above first letter row (Apple: ~8–12).
    var topInset: CGFloat { boardWidth >= 400 ? 8 : 10 }
    /// Bottom padding under last row (Apple: ~3–4 + home indicator is outside).
    var bottomInset: CGFloat { boardWidth >= 400 ? 4 : 3 }

    /// Visible key face height — linear fit from Apple measurements (39@320 → 43@375 → 46@414).
    var keyHeight: CGFloat {
        let h = boardWidth * (4.0 / 55.0) + 15.727
        return min(46, max(39, h.rounded()))
    }

    /// Letter face width for an N-key row that spans the full usable width.
    func letterWidth(columns: CGFloat = 11) -> CGFloat {
        let inner = boardWidth - sideMargin * 2
        let gaps = (columns - 1) * keyGap
        return (inner - gaps) / columns
    }

    /// Column pitch (face + trailing gap), used to size Shift/Delete as 2 columns.
    func pitch(columns: CGFloat = 11) -> CGFloat {
        letterWidth(columns: columns) + keyGap
    }

    /// Shift / Delete on German row 3 occupy 2 columns (Apple: ⇧ + 7 letters + ⌫ = 11).
    func shiftDeleteWidth(letterColumns: CGFloat = 11) -> CGFloat {
        2 * pitch(columns: letterColumns) - keyGap
    }

    /// Bottom-row special keys (123 / punct) — Apple ~40.5–46 “including gap”.
    func specialWidth(letterColumns: CGFloat = 11) -> CGFloat {
        let p = pitch(columns: letterColumns)
        return min(max(p * 1.28 - keyGap, 36), 50)
    }

    /// Return key — Apple ~87.5–97 “including gap” on portrait phones.
    func returnWidth(letterColumns: CGFloat = 11) -> CGFloat {
        let p = pitch(columns: letterColumns)
        return min(max(p * 2.65 - keyGap, 72), 100)
    }

    var cornerRadius: CGFloat {
        if boardWidth >= 400 { return 6 }
        if boardWidth >= 370 { return 5 }
        return 4.5
    }
}

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
        GeometryReader { geo in
            let m = AppleKeyboardMetrics(boardWidth: geo.size.width)
            VStack(spacing: m.rowGap) {
                if model.showingNumbers {
                    numbersLayout(m)
                } else {
                    lettersLayout(m)
                }
            }
            .padding(.horizontal, m.sideMargin)
            .padding(.top, m.topInset)
            .padding(.bottom, m.bottomInset)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .animation(.easeOut(duration: 0.15), value: model.showingNumbers)
        }
        // Letter block ~ 4 rows × keyH + 3 gaps + insets ≈ Apple letter area (~216 without toolbar).
        .frame(height: letterBlockHeight)
    }

    private var letterBlockHeight: CGFloat {
        // Approximate with mid-size phone metrics; GeometryReader refines face sizes.
        let probe = AppleKeyboardMetrics(boardWidth: 390)
        return probe.topInset + probe.bottomInset
            + probe.keyHeight * 4
            + probe.rowGap * 3
    }

    private func lettersLayout(_ m: AppleKeyboardMetrics) -> some View {
        let letterW = m.letterWidth(columns: 11)
        let shiftW = m.shiftDeleteWidth(letterColumns: 11)
        return VStack(spacing: m.rowGap) {
            // German iOS: rows 1+2 are 11 equal keys, edge-to-edge (no English A-row inset).
            letterRow(row1, width: letterW, height: m.keyHeight, gap: m.keyGap, radius: m.cornerRadius, size: .top)
            letterRow(row2, width: letterW, height: m.keyHeight, gap: m.keyGap, radius: m.cornerRadius, size: .middle)
            HStack(spacing: m.keyGap) {
                ModifierKey(
                    symbol: model.capsLock ? "capslock.fill" : "shift.fill",
                    width: shiftW,
                    height: m.keyHeight,
                    cornerRadius: m.cornerRadius,
                    active: model.shiftOn || model.capsLock
                ) {
                    model.toggleShift()
                }
                letterRowContent(row3, width: letterW, height: m.keyHeight, gap: m.keyGap, radius: m.cornerRadius, size: .bottom)
                DeleteKey(width: shiftW, height: m.keyHeight, cornerRadius: m.cornerRadius) {
                    model.beginDeleteHold()
                } onEnd: {
                    model.endDeleteHold()
                }
            }
            bottomRow(leftTitle: "123", metrics: m, letterColumns: 11)
        }
    }

    private func numbersLayout(_ m: AppleKeyboardMetrics) -> some View {
        // Numbers pad uses 10 columns (Apple numbers/punctuation layout).
        let letterW = m.letterWidth(columns: 10)
        let shiftW = m.shiftDeleteWidth(letterColumns: 10)
        return VStack(spacing: m.rowGap) {
            letterRow(num1, width: letterW, height: m.keyHeight, gap: m.keyGap, radius: m.cornerRadius, size: .top)
            letterRow(num2, width: letterW, height: m.keyHeight, gap: m.keyGap, radius: m.cornerRadius, size: .middle)
            HStack(spacing: m.keyGap) {
                ModifierKey(title: "#+=", width: shiftW, height: m.keyHeight, cornerRadius: m.cornerRadius) {
                    model.insert("#")
                }
                // 6 symbols + 2-col shift/delete = 10 columns (same span as rows above).
                letterRowContent(num3, width: letterW, height: m.keyHeight, gap: m.keyGap, radius: m.cornerRadius, size: .bottom)
                DeleteKey(width: shiftW, height: m.keyHeight, cornerRadius: m.cornerRadius) {
                    model.beginDeleteHold()
                } onEnd: {
                    model.endDeleteHold()
                }
            }
            bottomRow(leftTitle: "ABC", metrics: m, letterColumns: 10)
        }
    }

    private func bottomRow(leftTitle: String, metrics m: AppleKeyboardMetrics, letterColumns: CGFloat) -> some View {
        let special = m.specialWidth(letterColumns: letterColumns)
        let ret = m.returnWidth(letterColumns: letterColumns)
        return HStack(spacing: m.keyGap) {
            ModifierKey(title: leftTitle, width: special, height: m.keyHeight, cornerRadius: m.cornerRadius) {
                model.toggleNumbers()
            }
            PunctuationKey(width: special, height: m.keyHeight, cornerRadius: m.cornerRadius) { inserted in
                model.insert(inserted)
            }
            SpaceKey(height: m.keyHeight, cornerRadius: m.cornerRadius) {
                model.space()
            } onCursorMove: { model.moveCursor(by: $0) }
            ModifierKey(
                title: returnTitle,
                width: ret,
                height: m.keyHeight,
                cornerRadius: m.cornerRadius,
                prominent: false
            ) {
                model.returnKey()
            }
        }
    }

    private var returnTitle: String {
        model.showAskPanel ? "senden" : "return"
    }

    private func letterRow(
        _ chars: [Character],
        width: CGFloat,
        height: CGFloat,
        gap: CGFloat,
        radius: CGFloat,
        size: LetterKey.SizeClass
    ) -> some View {
        HStack(spacing: gap) {
            letterRowContent(chars, width: width, height: height, gap: gap, radius: radius, size: size)
        }
    }

    private func letterRowContent(
        _ chars: [Character],
        width: CGFloat,
        height: CGFloat,
        gap: CGFloat,
        radius: CGFloat,
        size: LetterKey.SizeClass
    ) -> some View {
        HStack(spacing: gap) {
            ForEach(Array(chars.enumerated()), id: \.offset) { _, ch in
                let label = display(ch)
                LetterKey(
                    label: label,
                    width: width,
                    height: height,
                    cornerRadius: radius,
                    size: size,
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
            "a": "aäàáâæãåā@",
            "e": "eèéêëēėę€",
            "i": "iìíîïīį",
            "o": "oöòóôõøōœ",
            "u": "uüùúûū",
            "s": "sßśš$",
            "n": "nñń",
            "c": "cçćč©",
            "y": "yÿý",
            "z": "zžźż",
            "ä": "äæ",
            "ö": "öøœ",
            "ü": "ü",
            "ß": "ßss",
            "d": "dð",
            "l": "lł",
            "r": "rř",
            "t": "tþ",
            "g": "gğ",
            "q": "q@",
            "w": "wŵ",
            "x": "x×",
            "b": "bß",
            "m": "mµ",
            "p": "p¶",
            "k": "kķ",
            "f": "fƒ",
            "h": "hħ",
            "j": "jȷ",
            "v": "v√",
            "1": "1¹½⅓¼¡",
            "2": "2²½⅔",
            "3": "3³¾⅓",
            "4": "4¼€£¥",
            "5": "5‰",
            "0": "0°∅",
            "-": "-–—_",
            "/": "/\\÷|",
            ":": ":;…",
            ";": ";:",
            "(": "()[]{}",
            ")": ")(][}{",
            "€": "€$£¥₩",
            "&": "&§@",
            "@": "@©®",
            "\"": "\"„“”«»",
            ".": ".,?!…·•",
            ",": ",;:",
            "?": "?¿!",
            "!": "!¡?",
            "'": "'‘’‛"
        ]
        guard let chars = map[lower] ?? map[String(first)] else {
            // Fallback: letter + common punctuation siblings so every key has a long-press menu
            if first.isLetter {
                return upper
                    ? [label, ".", ",", "!", "?", "-", "'"]
                    : [lower, ".", ",", "!", "?", "-", "'"]
            }
            return [String(first)]
        }
        let variants = chars.map { String($0) }
        if upper {
            return variants.map { $0.uppercased() }
        }
        return variants
    }
}

// MARK: - Letter key with popup + long-press accents

private struct LetterKey: View {
    enum SizeClass {
        case top, middle, bottom
    }

    let label: String
    var width: CGFloat = 28
    var height: CGFloat = 43
    var cornerRadius: CGFloat = 5
    var size: SizeClass = .top
    let accents: [String]
    var onInsert: (String) -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var pressed = false
    @State private var showAccents = false
    @State private var accentIndex = 0
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        Text(label)
            // Apple letter glyphs are modest; face size comes from width×height.
            .font(.system(size: letterSize, weight: .regular))
            .offset(y: -0.5)
            .foregroundStyle(.white)
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(keyFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(pressed ? 0.06 : 0.12), lineWidth: 0.4)
                    )
                    .shadow(
                        color: .black.opacity(scheme == .dark ? 0.45 : 0.18),
                        radius: pressed ? 0 : 0.4,
                        y: pressed ? 0 : 0.8
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
            // Touch target slightly larger than the visible Apple key face.
            .padding(.horizontal, -keyGapPad)
            .padding(.vertical, 1.5)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged(handleChanged)
                    .onEnded(handleEnded)
            )
    }

    /// Half of Apple’s 6pt gap — expands hit box into the gutter without overlapping neighbors badly.
    private var keyGapPad: CGFloat { 2.5 }

    private var isUppercaseLetter: Bool {
        guard let c = label.first, c.isLetter else { return false }
        return label == label.uppercased() && label != label.lowercased()
    }

    private var letterSize: CGFloat {
        // Slightly smaller than older NOCO keys — closer to system keyboard weight.
        switch size {
        case .middle:
            return isUppercaseLetter ? 22 : 20.5
        case .top, .bottom:
            return isUppercaseLetter ? 21 : 19.5
        }
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
        // Apple dark keyboard key tone
        if pressed {
            return Color(white: 0.55)
        }
        return Color(red: 0.39, green: 0.39, blue: 0.41)
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
                try? await Task.sleep(nanoseconds: 280_000_000)
                guard !Task.isCancelled else { return }
                if accents.count > 1 {
                    showAccents = true
                    accentIndex = min(1, accents.count - 1) // first accent after base
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.58)
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
    var width: CGFloat = 40
    var height: CGFloat = 43
    var cornerRadius: CGFloat = 5
    var glyphLift: CGFloat = 0
    var onInsert: (String) -> Void

    private let marks = [".", ",", ";", ":", "!", "?", "…", "·", "—", "'", "\"", "„", "“", "(", ")", "@"]

    @Environment(\.colorScheme) private var scheme
    @State private var pressed = false
    @State private var showPicker = false
    @State private var pickIndex = 0
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        Text(".")
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .offset(y: -glyphLift)
            .frame(width: width, height: height)
            .foregroundStyle(.white.opacity(0.95))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(red: 0.30, green: 0.30, blue: 0.32))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
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
            .padding(.vertical, 1.5)
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
                        .font(.system(size: 20, weight: .medium))
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
                .font(.system(size: 28, weight: .semibold))
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
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.58)
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
    var height: CGFloat = 43
    var cornerRadius: CGFloat = 5
    var onBegin: () -> Void
    var onEnd: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var pressed = false

    var body: some View {
        Image(systemName: "delete.backward")
            .font(.system(size: 17, weight: .semibold))
            .frame(width: width, height: height)
            .foregroundStyle(.white.opacity(0.9))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(red: 0.30, green: 0.30, blue: 0.32))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
            .scaleEffect(pressed ? 0.96 : 1)
            .padding(.vertical, 1.5)
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
    var height: CGFloat = 43
    var cornerRadius: CGFloat = 5
    var active = false
    var prominent = false
    var glyphLift: CGFloat = 0
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
                    .font(.system(size: title.count > 6 ? 12 : (title == "return" ? 15 : 13), weight: .semibold))
            }
        }
        .offset(y: -glyphLift)
        .frame(width: width, height: height)
        .foregroundStyle(prominent ? .white : .white.opacity(0.9))
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
        .padding(.vertical, 1.5)
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
            return AnyShapeStyle(Color(white: 0.55))
        }
        // Apple modifier key (darker than letters)
        return AnyShapeStyle(Color(red: 0.30, green: 0.30, blue: 0.32))
    }
}

private struct SpaceKey: View {
    var height: CGFloat = 43
    var cornerRadius: CGFloat = 5
    var glyphLift: CGFloat = 0
    var onTap: () -> Void
    var onCursorMove: (Int) -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var pressed = false
    @State private var trackpad = false
    @State private var holdTask: Task<Void, Never>?
    @State private var lastDragX: CGFloat = 0
    @State private var accumX: CGFloat = 0

    var body: some View {
        Text(trackpad ? "Cursor" : "Leertaste")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
            .offset(y: -glyphLift)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        trackpad
                        ? Color(red: 0.28, green: 0.38, blue: 0.55)
                        : Color(red: 0.39, green: 0.39, blue: 0.41).opacity(pressed ? 0.88 : 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(trackpad ? 0.22 : 0.08), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.22), radius: 0.4, y: 1)
            )
            .padding(.vertical, 1.5)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged(handleChanged)
                    .onEnded(handleEnded)
            )
    }

    private func handleChanged(_ value: DragGesture.Value) {
        if !pressed {
            pressed = true
            trackpad = false
            lastDragX = value.location.x
            accumX = 0
            holdTask?.cancel()
            holdTask = Task {
                try? await Task.sleep(nanoseconds: 380_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    trackpad = true
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
                }
            }
        }
        guard trackpad else { return }
        let dx = value.location.x - lastDragX
        lastDragX = value.location.x
        accumX += dx
        let step: CGFloat = 8
        while accumX <= -step {
            accumX += step
            onCursorMove(-1)
        }
        while accumX >= step {
            accumX -= step
            onCursorMove(1)
        }
    }

    private func handleEnded(_ value: DragGesture.Value) {
        holdTask?.cancel()
        holdTask = nil
        let wasTrackpad = trackpad
        pressed = false
        trackpad = false
        accumX = 0
        if wasTrackpad {
            // Cursor move only — no space
            return
        }
        // Tiny movement still counts as tap
        onTap()
    }
}
