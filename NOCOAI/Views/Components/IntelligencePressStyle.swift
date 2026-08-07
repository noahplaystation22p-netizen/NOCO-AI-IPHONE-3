import SwiftUI



/// Soft press scale + haptic — Apple Intelligence tile feel.

struct IntelligencePressStyle: ButtonStyle {

    var haptic: () -> Void = { HapticService.light() }

    var scale: CGFloat = 0.965



    func makeBody(configuration: Configuration) -> some View {

        configuration.label

            .scaleEffect(configuration.isPressed ? scale : 1)

            .brightness(configuration.isPressed ? -0.02 : 0)

            .opacity(configuration.isPressed ? 0.94 : 1)

            .animation(.spring(response: 0.26, dampingFraction: 0.68), value: configuration.isPressed)

            .onChange(of: configuration.isPressed) { _, pressed in

                if pressed { haptic() }

            }

    }

}



/// Slightly stronger press for primary actions.

struct IntelligencePrimaryPressStyle: ButtonStyle {

    var haptic: () -> Void = { HapticService.medium() }



    func makeBody(configuration: Configuration) -> some View {

        configuration.label

            .scaleEffect(configuration.isPressed ? 0.955 : 1)

            .shadow(

                color: NOCORainbow.violet.opacity(configuration.isPressed ? 0.08 : 0.2),

                radius: configuration.isPressed ? 4 : 12,

                y: configuration.isPressed ? 1 : 5

            )

            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)

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


