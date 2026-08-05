import SwiftUI

enum NOCOAITheme {
    /// Soft Intelligence blue
    static let accent = Color(red: 0.32, green: 0.52, blue: 0.98)
    static let accentSecondary = Color(red: 0.48, green: 0.68, blue: 1.0)
    static let success = Color(red: 0.22, green: 0.80, blue: 0.52)
    static let danger = Color(red: 0.95, green: 0.32, blue: 0.36)

    static let glowPrimary = Color(red: 0.42, green: 0.68, blue: 1.0)
    static let glowSecondary = Color(red: 0.45, green: 0.88, blue: 0.82)
    static let glowAccent = Color(red: 0.78, green: 0.72, blue: 0.98)

    static func intelligenceBackground(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.04, blue: 0.07),
                    Color(red: 0.06, green: 0.07, blue: 0.11),
                    Color(red: 0.045, green: 0.05, blue: 0.085)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color(red: 0.96, green: 0.97, blue: 1.0),
                Color(red: 0.93, green: 0.95, blue: 0.99),
                Color(red: 0.97, green: 0.96, blue: 0.99)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func background(for scheme: ColorScheme) -> LinearGradient {
        intelligenceBackground(for: scheme)
    }

    static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.68)
    }

    static func cardStroke(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.045)
    }

    static func primaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : Color(red: 0.09, green: 0.10, blue: 0.14)
    }

    static func secondaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.58) : Color.black.opacity(0.48)
    }
}

struct GlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background {
            IntelligenceAtmosphere()
        }
    }
}

extension View {
    func nocoBackground() -> some View {
        modifier(GlassBackground())
    }
}
