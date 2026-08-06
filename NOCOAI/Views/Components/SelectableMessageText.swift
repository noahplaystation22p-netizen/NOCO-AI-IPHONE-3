import SwiftUI
import UIKit

/// Native selectable text — long-press marks words; system Copy uses the selection only.
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
        // Keep native edit menu so Copy uses the selected range, not the whole string.
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

/// Avoids selecting the entire message on the first long-press.
private final class MessageSelectTextView: UITextView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Let long-press selection start on the word under the finger.
        bounds.contains(point)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        // Prefer copy of selection; hide "Select All" spam that leads to whole-message copy.
        if action == #selector(selectAll(_:)) {
            return selectedRange.length == 0
        }
        return super.canPerformAction(action, withSender: sender)
    }
}
