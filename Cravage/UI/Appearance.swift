import SwiftUI
import UIKit

/// Light or dark, chosen in Settings. "Same as phone" follows the phone's own setting; the other
/// two override it for this app only. Saved on this phone (the privacy policy lists it).
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let key = "appearance"

    var id: Self { self }

    var title: String {
        switch self {
        case .system: return "Same as phone"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// For the window: `.unspecified` hands the choice back to the phone.
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    static func saved(in defaults: UserDefaults = .standard) -> Appearance {
        defaults.string(forKey: key).flatMap(Appearance.init(rawValue:)) ?? .system
    }
}

/// Applies the choice to the whole window. SwiftUI's preferredColorScheme changed the screen at once
/// but left a sheet already shown (Settings) in the old look until it closed; every screen presented
/// in a window follows the window's own setting.
struct WindowAppearance: UIViewRepresentable {
    let appearance: Appearance

    func makeUIView(context: Context) -> WindowAppearanceAnchor { WindowAppearanceAnchor() }

    func updateUIView(_ uiView: WindowAppearanceAnchor, context: Context) {
        uiView.appearance = appearance
    }
}

final class WindowAppearanceAnchor: UIView {
    var appearance: Appearance = .system {
        didSet { apply() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        apply()
    }

    private func apply() {
        window?.overrideUserInterfaceStyle = appearance.userInterfaceStyle
    }
}

