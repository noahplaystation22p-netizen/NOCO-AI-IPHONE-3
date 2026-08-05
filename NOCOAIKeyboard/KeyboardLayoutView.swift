import SwiftUI

/// Apple-like QWERTY / numbers with modern continuous keys.
struct KeyboardLayoutView: View {
    @ObservedObject var model: KeyboardViewModel
    @Environment(\.colorScheme) private var scheme

    private let row1 = Array("qwertyuiop")
    private let row2 = Array("asdfghjkl")
    private let row3 = Array("zxcvbnm")

    private let num1 = Array("1234567890")
    private let num2 = Array("-/:;()€&@\"")
    private let num3 = Array(".,?!'" )

    var body: some View {
        VStack(spacing: 7) {
            if model.showingNumbers {
                numbersLayout
            } else {
                lettersLayout
            }
        }
        .padding(.horizontal, 3)
        .animation(.easeOut(duration: 0.18), value: model.showingNumbers)
    }

    private var lettersLayout: some View {
        VStack(spacing: 7) {
            letterRow(row1)
            letterRow(row2, sidePad: 16)
            HStack(spacing: 5) {
                ModifierKey(symbol: model.capsLock ? "capslock.fill" : "shift.fill",
                            width: 44, active: model.shiftOn || model.capsLock) {
                    model.toggleShift()
                }
                letterRowContent(row3)
                ModifierKey(symbol: "delete.backward", width: 44) {
                    model.deleteBackward()
                }
            }
            bottomRow(leftTitle: "123")
        }
    }

    private var numbersLayout: some View {
        VStack(spacing: 7) {
            letterRow(num1)
            letterRow(num2)
            HStack(spacing: 5) {
                ModifierKey(title: "#+=", width: 44) {
                    model.insert("#")
                }
                letterRowContent(num3)
                ModifierKey(symbol: "delete.backward", width: 44) {
                    model.deleteBackward()
                }
            }
            bottomRow(leftTitle: "ABC")
        }
    }

    private func bottomRow(leftTitle: String) -> some View {
        HStack(spacing: 5) {
            ModifierKey(title: leftTitle, width: 44) {
                model.toggleNumbers()
            }
            ModifierKey(symbol: "globe", width: 44) {
                model.nextKeyboard()
            }
            SpaceKey {
                model.space()
            }
            ModifierKey(title: "return", width: 72, prominent: true) {
                model.returnKey()
            }
        }
    }

    private func letterRow(_ chars: [Character], sidePad: CGFloat = 0) -> some View {
        HStack(spacing: 5) {
            if sidePad > 0 { Spacer(minLength: sidePad) }
            letterRowContent(chars)
            if sidePad > 0 { Spacer(minLength: sidePad) }
        }
    }

    private func letterRowContent(_ chars: [Character]) -> some View {
        HStack(spacing: 5) {
            ForEach(chars, id: \.self) { ch in
                LetterKey(label: display(ch)) {
                    model.insert(display(ch))
                }
            }
        }
    }

    private func display(_ ch: Character) -> String {
        let s = String(ch)
        return (model.shiftOn || model.capsLock) ? s.uppercased() : s
    }
}

private struct LetterKey: View {
    let label: String
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 22, weight: .regular, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(keyFill)
                        .shadow(
                            color: .black.opacity(scheme == .dark ? 0.35 : 0.16),
                            radius: pressed ? 0 : 0.5,
                            y: pressed ? 0 : 1
                        )
                )
                .scaleEffect(pressed ? 0.96 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed { pressed = true }
                }
                .onEnded { _ in pressed = false }
        )
        .animation(.easeOut(duration: 0.08), value: pressed)
    }

    private var keyFill: Color {
        scheme == .dark
            ? Color(white: pressed ? 0.38 : 0.45)
            : Color.white.opacity(pressed ? 0.85 : 1)
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

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                } else if let title {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
            }
            .frame(width: width, height: 42)
            .foregroundStyle(prominent ? .white : .primary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fill)
            )
        }
        .buttonStyle(.plain)
    }

    private var fill: Color {
        if prominent {
            return Color(red: 0.28, green: 0.48, blue: 0.98)
        }
        if active {
            return scheme == .dark ? Color.white.opacity(0.55) : Color.white
        }
        return scheme == .dark ? Color(white: 0.28) : Color(white: 0.72)
    }
}

private struct SpaceKey: View {
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Text("Leertaste")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(scheme == .dark ? Color(white: 0.45) : Color.white)
                        .shadow(color: .black.opacity(0.12), radius: 0.5, y: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
