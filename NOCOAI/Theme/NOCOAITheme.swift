import SwiftUI

enum NOCOAITheme {
    /// Soft system blue — Apple Intelligence adjacent, not purple-AI cliché
    static let accent = Color(red: 0.20, green: 0.48, blue: 0.96)
    static let accentSecondary = Color(red: 0.35, green: 0.62, blue: 1.0)
    static let success = Color(red: 0.20, green: 0.78, blue: 0.45)
    static let danger = Color(red: 0.95, green: 0.30, blue: 0.30)

    static func intelligenceBackground(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.07),
                    Color(red: 0.08, green: 0.09, blue: 0.12),
                    Color(red: 0.06, green: 0.07, blue: 0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [
                Color(red: 0.96, green: 0.97, blue: 0.99),
                Color(red: 0.93, green: 0.95, blue: 0.98),
                Color.white
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func background(for scheme: ColorScheme) -> LinearGradient {
        intelligenceBackground(for: scheme)
    }

    static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.70)
    }

    static func cardStroke(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.05)
    }

    static func primaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : Color(red: 0.10, green: 0.10, blue: 0.12)
    }

    static func secondaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.50)
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
