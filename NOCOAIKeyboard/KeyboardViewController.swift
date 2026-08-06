import UIKit
import SwiftUI

final class KeyboardViewController: UIInputViewController {
    private var hosting: UIHostingController<KeyboardRootView>?
    private let model = KeyboardViewModel()
    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        model.bind(controller: self)

        let root = KeyboardRootView(model: model)
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        hosting = host
        updateKeyboardHeight()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.refreshAccess()
        model.syncDocumentSnapshot()
        updateKeyboardHeight()
    }

    /// Custom schemes often fail via `extensionContext.open` from keyboards — use responder chain.
    func openURL(_ url: URL) {
        var responder: UIResponder? = self
        while let r = responder {
            let sel = Selector(("openURL:"))
            if r.responds(to: sel) {
                r.perform(sel, with: url)
                return
            }
            responder = r.next
        }
        extensionContext?.open(url) { [weak self] ok in
            DispatchQueue.main.async {
                if !ok {
                    self?.model.statusLine = "App öffnen fehlgeschlagen — Vollzugriff?"
                }
            }
        }
    }

    func updateKeyboardHeight() {
        let hasAsk = model.showAskPanel
        let hasReply = !model.askReply.isEmpty
        let needed: CGFloat
        if hasAsk && hasReply {
            needed = 470
        } else if hasAsk {
            needed = 390
        } else {
            needed = 318
        }
        if let heightConstraint {
            heightConstraint.constant = needed
        } else {
            let c = view.heightAnchor.constraint(equalToConstant: needed)
            c.priority = .required
            c.isActive = true
            heightConstraint = c
        }
        view.setNeedsUpdateConstraints()
        UIView.animate(withDuration: 0.25) {
            self.view.superview?.layoutIfNeeded()
        }
    }

    override func updateViewConstraints() {
        updateKeyboardHeight()
        super.updateViewConstraints()
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        model.syncDocumentSnapshot()
    }
}
