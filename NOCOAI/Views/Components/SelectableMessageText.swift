import SwiftUI
import UIKit

/// Native selectable text — long-press marks words; system Copy uses the selection only.
/// Whole-message copy is only via the copy icon in the action row.
struct SelectableMessageText: UIViewRepresentable {
    let text: String
    var textColor: UIColor
    var font: UIFont = .preferredFont(forTextStyle: .body)

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextView {
        let tv = MessageSelectTextView()
        tv.backgroundColor = .clear
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.dataDetectorTypes = []
        tv.font = font
        tv.textColor = textColor
        tv.text = text
        tv.delegate = context.coordinator
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            let selected = uiView.selectedRange
            uiView.text = text
            if selected.length > 0, NSMaxRange(selected) <= (text as NSString).length {
                uiView.selectedRange = selected
            }
        }
        uiView.textColor = textColor
        uiView.font = font
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 280
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }

    final class Coordinator: NSObject, UITextViewDelegate {}
}

/// Long-press selects the word under the finger — never auto-selects the whole bubble.
private final class MessageSelectTextView: UITextView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(selectAll(_:)) {
            return false
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func selectAll(_ sender: Any?) {
        // Disabled — whole message is only via the copy icon.
    }
}
