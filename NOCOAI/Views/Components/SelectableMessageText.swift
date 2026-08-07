import SwiftUI
import UIKit

/// Native selectable text — long-press opens iOS selection (cursor, grips, words).
/// Action row still offers whole-message Copy / Share / Speak.
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
        tv.isUserInteractionEnabled = true
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.defaultHigh, for: .vertical)
        tv.dataDetectorTypes = []
        tv.font = font
        tv.textColor = textColor
        tv.text = text
        tv.delegate = context.coordinator
        // Native edit menu: Copy / Select / Select All / Share…
        tv.allowsEditingTextAttributes = false
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            let selected = uiView.selectedRange
            uiView.text = text
            let maxLen = (text as NSString).length
            if selected.length > 0, NSMaxRange(selected) <= maxLen {
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

    final class Coordinator: NSObject, UITextViewDelegate {
        func textViewDidChangeSelection(_ textView: UITextView) {
            // Keep selection visible; no-op otherwise.
        }
    }
}

/// Forwards long-press to the system text selection UI (grips + cursor).
private final class MessageSelectTextView: UITextView {
    override var canBecomeFirstResponder: Bool { true }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        // Ensure we can present the edit menu after a selection gesture.
        if !isFirstResponder {
            _ = becomeFirstResponder()
        }
    }
}
