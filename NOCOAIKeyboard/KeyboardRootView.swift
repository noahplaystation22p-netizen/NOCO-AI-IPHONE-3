import SwiftUI

struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardViewModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            aiToolbar
            statusBar
            KeyboardLayoutView(model: model)
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
        }
        .padding(.top, 6)
        .background(keyboardBackground)
        .overlay {
            if model.isProcessing {
                processingOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.isProcessing)
    }

    private var aiToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(KeyboardAIAction.allCases) { action in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            model.run(action)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: action.systemImage)
                                .font(.caption.weight(.semibold))
                            Text(action.title)
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(chipFill(for: action))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(chipStroke, lineWidth: 1)
                                )
                                .shadow(
                                    color: action == .noco
                                        ? Color(red: 0.35, green: 0.45, blue: 1).opacity(0.35)
                                        : .clear,
                                    radius: 6, y: 1
                                )
                        )
                        .foregroundStyle(chipForeground(for: action))
                    }
                    .buttonStyle(SoftPressStyle())
                    .disabled(model.isProcessing)
                    .opacity(model.isProcessing ? 0.55 : 1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .shadow(color: statusColor.opacity(0.75), radius: 3)
                .animation(.easeInOut(duration: 0.35), value: statusColor.description)
            Text(model.statusLine)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
            if model.isProcessing {
                ProgressView()
                    .scaleEffect(0.65)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    private var processingOverlay: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial.opacity(0.28))
            .overlay(
                HStack(spacing: 10) {
                    ProgressView()
                    Text("NOCO schreibt…")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            )
            .allowsHitTesting(false)
    }

    private var keyboardBackground: some View {
        ZStack {
            (scheme == .dark
             ? Color(red: 0.11, green: 0.11, blue: 0.12)
             : Color(red: 0.82, green: 0.83, blue: 0.85))
            LinearGradient(
                colors: [
                    Color.white.opacity(scheme == .dark ? 0.05 : 0.4),
                    .clear
                ],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }

    private var statusColor: Color {
        if !model.hasFullAccess || !model.isConfigured { return .orange }
        if model.isProcessing { return Color(red: 0.35, green: 0.65, blue: 1) }
        if model.lastError != nil { return .red }
        return Color(red: 0.25, green: 0.82, blue: 0.5)
    }

    private func chipFill(for action: KeyboardAIAction) -> some ShapeStyle {
        if action == .noco {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.32, green: 0.52, blue: 1),
                        Color(red: 0.52, green: 0.42, blue: 0.95)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }

    private func chipForeground(for action: KeyboardAIAction) -> Color {
        action == .noco ? .white : .primary
    }

    private var chipStroke: Color {
        scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
    }
}

private struct SoftPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
