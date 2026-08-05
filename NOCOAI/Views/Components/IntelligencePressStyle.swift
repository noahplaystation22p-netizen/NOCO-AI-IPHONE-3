import SwiftUI

/// Soft press scale + haptic — Apple Intelligence tile feel.
struct IntelligencePressStyle: ButtonStyle {
    var haptic: () -> Void = { HapticService.light() }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { haptic() }
            }
    }
}

extension View {
    /// Layered sensory feedback for value changes (iOS 17+).
    func intelligenceSelectionFeedback<T: Equatable>(_ value: T) -> some View {
        sensoryFeedback(.selection, trigger: value)
    }

    func intelligenceSuccessFeedback(_ trigger: Bool) -> some View {
        sensoryFeedback(.success, trigger: trigger)
    }

    func intelligenceImpactFeedback<T: Equatable>(_ value: T) -> some View {
        sensoryFeedback(.impact(flexibility: .soft, intensity: 0.55), trigger: value)
    }
}
