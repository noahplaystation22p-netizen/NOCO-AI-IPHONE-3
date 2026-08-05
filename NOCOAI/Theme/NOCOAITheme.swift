import SwiftUI

enum NOCOAITheme {
    static let accent = Color(red: 0.22, green: 0.52, blue: 0.98)
    static let accentSecondary = Color(red: 0.38, green: 0.72, blue: 0.98)
    static let success = Color(red: 0.20, green: 0.78, blue: 0.45)
    static let danger = Color(red: 0.95, green: 0.30, blue: 0.30)

    static let glowPrimary = Color(red: 0.35, green: 0.72, blue: 1.0)
    static let glowSecondary = Color(red: 0.45, green: 0.85, blue: 0.78)
    static let glowAccent = Color(red: 0.85, green: 0.78, blue: 0.65)

    static func intelligenceBackground(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.08),
                    Color(red: 0.07, green: 0.08, blue: 0.12),
                    Color(red: 0.05, green: 0.06, blue: 0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.97, blue: 1.0),
                Color(red: 0.92, green: 0.95, blue: 0.99),
                Color.white
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func background(for scheme: ColorScheme) -> LinearGradient {
        intelligenceBackground(for: scheme)
    }

    static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.09) : Color.white.opacity(0.72)
    }

    static func cardStroke(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.05)
    }

    static func primaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : Color(red: 0.10, green: 0.10, blue: 0.12)
    }

    static func secondaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.50)
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
