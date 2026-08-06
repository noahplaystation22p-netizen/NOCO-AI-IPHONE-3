import SwiftUI
import UIKit

/// Quick tool list for Plus long-press: hold, slide, release to select.
enum PlusQuickAction: String, CaseIterable, Identifiable {
    case camera
    case vision
    case agent
    case createImage
    case file
    case writing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: return "Kamera"
        case .vision: return "Vision"
        case .agent: return "Agent"
        case .createImage: return "Bild erstellen"
        case .file: return "Datei"
        case .writing: return "Schreibwerkzeuge"
        }
    }

    var systemImage: String {
        switch self {
        case .camera: return "camera.fill"
        case .vision: return "eye.circle.fill"
        case .agent: return "cpu.fill"
        case .createImage: return "paintbrush.pointed.fill"
        case .file: return "folder.fill"
        case .writing: return "pencil.and.outline"
        }
    }

    var tint: Color {
        switch self {
        case .camera: return Color(red: 0.35, green: 0.75, blue: 1)
        case .vision: return Color(red: 0.45, green: 0.85, blue: 0.7)
        case .agent: return Color(red: 0.35, green: 0.78, blue: 0.72)
        case .createImage: return Color(red: 0.95, green: 0.55, blue: 0.78)
        case .file: return Color(red: 0.75, green: 0.65, blue: 0.45)
        case .writing: return Color(red: 0.62, green: 0.55, blue: 0.98)
        }
    }
}

/// Full-window overlay so the quick list is not clipped by the input bar.
@MainActor
enum PlusQuickPickerWindow {
    private static var host: UIWindow?
    private static var model = PlusQuickPickerModel()

    static func show(anchor: CGPoint, highlight: PlusQuickAction = .camera) {
        model.highlighted = highlight
        model.anchor = anchor
        model.finger = anchor
        guard host == nil else { return }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }

        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = false
        let root = UIHostingController(rootView: PlusQuickPickerOverlay(model: model))
        root.view.backgroundColor = .clear
        window.rootViewController = root
        window.isHidden = false
        host = window
    }

    static func update(finger: CGPoint?, highlight: PlusQuickAction?) {
        if let finger { model.finger = finger }
        if let highlight, model.highlighted != highlight {
            model.highlighted = highlight
            HapticService.selection()
        } else if finger != nil {
            model.recomputeHighlight()
        }
    }

    static var currentHighlight: PlusQuickAction? { model.highlighted }

    static func hide() {
        host?.isHidden = true
        host = nil
        model.highlighted = .camera
        model.finger = nil
    }
}

@MainActor
final class PlusQuickPickerModel: ObservableObject {
    @Published var highlighted: PlusQuickAction? = .camera
    @Published var anchor: CGPoint = .zero
    @Published var finger: CGPoint?

    private let rowHeight: CGFloat = 52
    private let actions = PlusQuickAction.allCases

    func recomputeHighlight() {
        guard let finger else {
            if highlighted == nil { highlighted = actions.first }
            return
        }
        let menuCenterY = max(180, anchor.y - 210)
        let menuTop = menuCenterY - (CGFloat(actions.count) * rowHeight + 28) / 2
        let relative = finger.y - menuTop - 14
        let index = Int(relative / (rowHeight + 4))
        let clamped = min(max(0, index), actions.count - 1)
        let next = actions[clamped]
        if highlighted != next {
            highlighted = next
            HapticService.selection()
        }
    }
}

struct PlusQuickPickerOverlay: View {
    @ObservedObject var model: PlusQuickPickerModel

    private let rowHeight: CGFloat = 52
    private let actions = PlusQuickAction.allCases

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()

                VStack(spacing: 4) {
                    ForEach(actions) { action in
                        HStack(spacing: 12) {
                            Image(systemName: action.systemImage)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(model.highlighted == action ? .white : action.tint)
                                .frame(width: 28)
                            Text(action.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(model.highlighted == action ? .white : .primary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: rowHeight)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(model.highlighted == action
                                      ? action.tint.opacity(0.95)
                                      : Color(.secondarySystemBackground).opacity(0.94))
                        }
                        .scaleEffect(model.highlighted == action ? 1.03 : 1)
                        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: model.highlighted)
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
                .frame(width: 240)
                .position(
                    x: min(max(model.anchor.x, 140), max(140, geo.size.width - 140)),
                    y: max(180, model.anchor.y - 210)
                )
            }
            .onChange(of: model.finger?.y) { _, _ in
                model.recomputeHighlight()
            }
            .onAppear {
                model.recomputeHighlight()
            }
        }
        .allowsHitTesting(false)
    }
}
