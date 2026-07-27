import SwiftUI

enum NOCOAITheme {
    static let accent = Color(red: 0.35, green: 0.62, blue: 1.0)
    static let accentSecondary = Color(red: 0.55, green: 0.35, blue: 1.0)
    static let success = Color(red: 0.2, green: 0.85, blue: 0.55)
    static let danger = Color(red: 1.0, green: 0.35, blue: 0.4)

    static func background(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.1),
                    Color(red: 0.08, green: 0.09, blue: 0.16),
                    Color(red: 0.05, green: 0.07, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.96, blue: 0.99),
                Color(red: 0.9, green: 0.93, blue: 0.98),
                Color.white
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.72)
    }

    static func cardStroke(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.06)
    }

    static func primaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : Color(red: 0.08, green: 0.09, blue: 0.12)
    }

    static func secondaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.55)
    }
}

struct GlassBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(NOCOAITheme.background(for: scheme).ignoresSafeArea())
    }
}

extension View {
    func nocoBackground() -> some View {
        modifier(GlassBackground())
    }
}
