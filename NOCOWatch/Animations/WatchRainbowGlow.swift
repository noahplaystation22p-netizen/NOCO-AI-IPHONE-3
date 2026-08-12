import SwiftUI
import WatchKit

/// Watch-optimized rainbow palette (fewer layers on legacy hardware).
enum WatchRainbow {
    static let blue = Color(red: 0.32, green: 0.72, blue: 1.0)
    static let violet = Color(red: 0.58, green: 0.42, blue: 1.0)
    static let pink = Color(red: 0.95, green: 0.42, blue: 0.78)
    static let green = Color(red: 0.35, green: 0.92, blue: 0.62)
    static let teal = Color(red: 0.28, green: 0.88, blue: 0.86)

    static var flow: [Color] { [blue, violet, pink, teal, green, blue] }
}

/// Performance tier — reduce blur/particles on older watches.
enum WatchRenderTier {
    case full
    case lite

    static var current: WatchRenderTier {
        #if os(watchOS)
        if WKInterfaceDevice.current().screenBounds.width <= 162 {
            return .lite
        }
        #endif
        return .full
    }
}

struct WatchRainbowGlow: View {
    var phase: WatchStatusSnapshot.Phase
    var level: CGFloat = 0.3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false

    private var tier: WatchRenderTier { .current }

    var body: some View {
        TimelineView(.animation(minimumInterval: tier == .lite ? 1.0 / 8.0 : 1.0 / 14.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                if tier == .full {
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: WatchRainbow.flow.map { $0.opacity(glowOpacity * 0.35) },
                                center: .center,
                                angle: .degrees(spin ? 360 : 0)
                            )
                        )
                        .blur(radius: 18)
                        .scaleEffect(1.15 + level * 0.08)
                }

                Circle()
                    .strokeBorder(
                        AngularGradient(colors: WatchRainbow.flow.map { $0.opacity(glowOpacity) }, center: .center),
                        lineWidth: tier == .lite ? 2.5 : 3.5
                    )
                    .blur(radius: tier == .lite ? 0 : 1.5)
                    .scaleEffect(1.02 + level * 0.04)
                    .rotationEffect(.degrees(reduceMotion ? 0 : t * spinSpeed))

                if phase == .listening || phase == .speaking {
                    Circle()
                        .stroke(WatchRainbow.teal.opacity(0.45 + Double(level) * 0.35), lineWidth: 1.2)
                        .scaleEffect(1.08 + level * 0.12)
                }
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: spinDuration).repeatForever(autoreverses: false)) {
                spin = true
            }
        }
    }

    private var glowOpacity: Double {
        switch phase {
        case .idle: return 0.55
        case .listening: return 0.75 + Double(level) * 0.2
        case .thinking, .connecting: return 0.82
        case .speaking: return 0.88
        case .error: return 0.4
        }
    }

    private var spinSpeed: Double {
        switch phase {
        case .idle: return 18
        case .listening: return 28
        case .thinking, .connecting: return 12
        case .speaking: return 22
        case .error: return 8
        }
    }

    private var spinDuration: Double {
        switch phase {
        case .thinking: return 5.5
        case .listening: return 8
        default: return 10
        }
    }
}

struct WatchIntelligenceCore: View {
    var phase: WatchStatusSnapshot.Phase
    var diameter: CGFloat = 88
    var level: CGFloat = 0.2

    var body: some View {
        ZStack {
            WatchRainbowGlow(phase: phase, level: level)
                .frame(width: diameter * 1.35, height: diameter * 1.35)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.black.opacity(0.85)
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: diameter * 0.55
                    )
                )
                .frame(width: diameter, height: diameter)

            Image(systemName: coreSymbol)
                .font(.system(size: diameter * 0.28, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: WatchRainbow.flow, startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .symbolEffect(.pulse, isActive: phase == .listening || phase == .thinking)
        }
        .accessibilityHidden(true)
    }

    private var coreSymbol: String {
        switch phase {
        case .listening: return "waveform"
        case .thinking, .connecting: return "sparkles"
        case .speaking: return "speaker.wave.2.fill"
        case .error: return "exclamationmark.triangle"
        case .idle: return "brain.head.profile"
        }
    }
}
