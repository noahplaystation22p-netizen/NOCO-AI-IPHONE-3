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
                    Color(red: 0.028, green: 0.032, blue: 0.055),
                    Color(red: 0.048, green: 0.055, blue: 0.095),
                    Color(red: 0.038, green: 0.042, blue: 0.072)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color(red: 0.965, green: 0.975, blue: 1.0),
                Color(red: 0.93, green: 0.945, blue: 0.99),
                Color(red: 0.97, green: 0.965, blue: 0.995)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func background(for scheme: ColorScheme) -> LinearGradient {
        intelligenceBackground(for: scheme)
    }

    static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.075) : Color.white.opacity(0.72)
    }

    static func cardStroke(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.04)
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
