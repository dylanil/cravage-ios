import SwiftUI
import UIKit

/// Installs a synchronous, whole-window cover before UIKit takes an app-switcher snapshot.
struct PrivacyShield: UIViewRepresentable {
    let onBackground: () -> Void

    func makeUIView(context: Context) -> PrivacyShieldAnchor {
        PrivacyShieldAnchor(onBackground: onBackground)
    }

    func updateUIView(_ uiView: PrivacyShieldAnchor, context: Context) {
        uiView.onBackground = onBackground
    }
}

final class PrivacyShieldAnchor: UIView {
    var onBackground: () -> Void
    private let cover = UILabel()

    init(onBackground: @escaping () -> Void) {
        self.onBackground = onBackground
        super.init(frame: .zero)
        cover.text = "Cravage"
        cover.textAlignment = .center
        cover.font = .preferredFont(forTextStyle: .largeTitle)
        cover.textColor = UIColor(Paper.ink)
        cover.backgroundColor = UIColor(Paper.paper)
        cover.isOpaque = true
        cover.accessibilityViewIsModal = true
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(deactivate), name: UIScene.willDeactivateNotification, object: nil)
        center.addObserver(self, selector: #selector(background), name: UIScene.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(activate), name: UIScene.didActivateNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        cover.removeFromSuperview()
        if let window, window.windowScene?.activationState != .foregroundActive { conceal() }
    }

    private func belongsToWindow(_ notification: Notification) -> Bool {
        guard let scene = notification.object as? UIScene, let ownScene = window?.windowScene else { return false }
        return scene === ownScene
    }

    private func conceal() {
        guard let window else { return }
        cover.frame = window.bounds
        window.addSubview(cover)
        window.bringSubviewToFront(cover)
        window.endEditing(true)
    }

    @objc private func deactivate(_ notification: Notification) {
        guard belongsToWindow(notification) else { return }
        conceal()
    }

    @objc private func background(_ notification: Notification) {
        guard belongsToWindow(notification) else { return }
        conceal()
        onBackground()
    }

    @objc private func activate(_ notification: Notification) {
        guard belongsToWindow(notification) else { return }
        cover.removeFromSuperview()
    }
}
