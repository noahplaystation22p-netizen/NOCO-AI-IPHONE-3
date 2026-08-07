import SwiftUI
import UIKit

/// Quick tool list for Plus long-press: hold, slide, release to select.
enum PlusQuickAction: String, CaseIterable, Identifiable {
    case camera
    case vision
    case liveWeb
    case agent
    case createImage
    case file
    case writing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: return "Kamera"
        case .vision: return "Vision"
        case .liveWeb: return "Internet"
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
        case .liveWeb: return "globe"
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
        case .liveWeb: return Color(red: 0.35, green: 0.65, blue: 0.95)
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

    /// Vertical lift above the + button (higher = sits further up).
    static let liftAboveAnchor: CGFloat = 248

    static func show(anchor: CGPoint, highlight: PlusQuickAction = .camera) {
        model.highlighted = highlight
        model.anchor = anchor
        model.finger = anchor
        model.visible = true
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

    static func hide(animated: Bool = true) {
        guard host != nil else {
            model.visible = false
            model.highlighted = .camera
            model.finger = nil
            return
        }
        if animated {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                model.visible = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                tearDown()
            }
        } else {
            tearDown()
        }
    }

    private static func tearDown() {
        host?.isHidden = true
        host = nil
        model.visible = false
        model.highlighted = .camera
        model.finger = nil
    }
}

@MainActor
final class PlusQuickPickerModel: ObservableObject {
    @Published var highlighted: PlusQuickAction? = .camera
    @Published var anchor: CGPoint = .zero
    @Published var finger: CGPoint?
    @Published var visible = false

    private let rowHeight: CGFloat = 52
    private let actions = PlusQuickAction.allCases

    func menuCenterY(in height: CGFloat) -> CGFloat {
        let ideal = anchor.y - PlusQuickPickerWindow.liftAboveAnchor
        let half = (CGFloat(actions.count) * rowHeight + 48) / 2
        return min(max(half + 24, ideal), height - half - 24)
    }

    func recomputeHighlight() {
        guard let finger else {
            if highlighted == nil { highlighted = actions.first }
            return
        }
        // Approximate using same lift as overlay (screen coords).
        let menuCenterY = max(160, anchor.y - PlusQuickPickerWindow.liftAboveAnchor)
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
                Color.black.opacity(model.visible ? 0.32 : 0)
                    .ignoresSafeArea()
                    .animation(.easeOut(duration: 0.22), value: model.visible)

                if model.visible {
                    NOCOIntelligenceCore(energy: .idle, size: .compact)
                        .opacity(0.35)
                        .blur(radius: 2)
                        .offset(y: -160)
                        .allowsHitTesting(false)
                }

                VStack(spacing: 4) {
                    ForEach(actions) { action in
                        HStack(spacing: 12) {
                            Image(systemName: action.systemImage)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(model.highlighted == action ? .white : action.tint)
                                .frame(width: 28)
                                .symbolEffect(.bounce, value: model.highlighted == action)
                            Text(action.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(model.highlighted == action ? .white : .primary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: rowHeight)
                        .background {
                            Group {
                                if model.highlighted == action {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [action.tint, action.tint.opacity(0.78)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                } else {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(.secondarySystemBackground).opacity(0.94))
                                }
                            }
                        }
                        .scaleEffect(model.highlighted == action ? 1.03 : 1)
                        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: model.highlighted)
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            AngularGradient(
                                colors: NOCORainbow.flow.map { $0.opacity(0.45) },
                                center: .center
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: NOCORainbow.violet.opacity(0.22), radius: 20, y: 8)
                .frame(width: 240)
                .scaleEffect(model.visible ? 1 : 0.86)
                .opacity(model.visible ? 1 : 0)
                .offset(y: model.visible ? 0 : 28)
                .position(
                    x: min(max(model.anchor.x, 140), max(140, geo.size.width - 140)),
                    y: model.menuCenterY(in: geo.size.height)
                )
                .animation(.spring(response: 0.34, dampingFraction: 0.82), value: model.visible)
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
