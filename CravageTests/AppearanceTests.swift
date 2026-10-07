import SwiftUI
import XCTest
@testable import Cravage

/// The Settings switch: "Same as phone" leaves the phone's setting in charge, the other two override
/// it, and the choice survives a relaunch.
final class AppearanceTests: XCTestCase {

    func testSameAsPhoneOverridesNothingAndTheOthersForceTheirLook() {
        XCTAssertEqual(Appearance.system.userInterfaceStyle, .unspecified)
        XCTAssertEqual(Appearance.light.userInterfaceStyle, .light)
        XCTAssertEqual(Appearance.dark.userInterfaceStyle, .dark)
    }

    func testTheSwitchOffersSameAsPhoneFirstAndItIsTheDefault() {
        XCTAssertEqual(Appearance.allCases.map(\.title), ["Same as phone", "Light", "Dark"])
        XCTAssertEqual(Appearance.saved(in: UserDefaults(suiteName: "appearance-empty-\(UUID())")!), .system)
    }

    func testTheChoiceIsReadBackAndAnUnknownValueFallsBackToSameAsPhone() {
        let defaults = UserDefaults(suiteName: "appearance-\(UUID())")!
        defaults.set(Appearance.dark.rawValue, forKey: Appearance.key)
        XCTAssertEqual(Appearance.saved(in: defaults), .dark)
        defaults.set("sepia", forKey: Appearance.key)
        XCTAssertEqual(Appearance.saved(in: defaults), .system)
    }

    /// On a phone, Settings (a sheet) kept the old look until it closed while the screen behind it
    /// changed at once: SwiftUI's preferredColorScheme does not reach a sheet already shown. Here a
    /// SwiftUI sheet is open when the choice changes, and must see the new look.
    @MainActor
    func testAnOpenSwiftUISheetSeesTheNewLook() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let model = SheetModel()
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = .unspecified
        window.rootViewController = UIHostingController(rootView: SheetHost(model: model))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(600))
        for choice in [Appearance.dark, .light, .dark] {
            model.appearance = choice
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertEqual(model.seenInSheet, choice == .dark ? .dark : .light, "\(choice)")
        }
    }
}

@MainActor
@Observable
private final class SheetModel {
    var appearance = Appearance.light
    var seenInSheet: ColorScheme?
}

private struct SheetHost: View {
    let model: SheetModel

    var body: some View {
        Color.clear
            .sheet(isPresented: .constant(true)) { SheetProbe(model: model) }
            .background(WindowAppearance(appearance: model.appearance))
    }
}

private struct SheetProbe: View {
    let model: SheetModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color.clear.onChange(of: colorScheme, initial: true) { model.seenInSheet = colorScheme }
    }
}

