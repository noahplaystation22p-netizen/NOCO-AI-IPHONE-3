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
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.refreshAccess()
        model.syncDocumentSnapshot()
    }

    override func updateViewConstraints() {
        let needed: CGFloat = 292
        if let heightConstraint {
            heightConstraint.constant = needed
        } else {
            let c = view.heightAnchor.constraint(equalToConstant: needed)
            c.priority = .defaultHigh
            c.isActive = true
            heightConstraint = c
        }
        super.updateViewConstraints()
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        model.syncDocumentSnapshot()
    }
}
