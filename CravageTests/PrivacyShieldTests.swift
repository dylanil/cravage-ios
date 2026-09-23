import XCTest
import UIKit
import SwiftUI
@testable import Cravage

@MainActor
final class PrivacyShieldTests: XCTestCase {
    func testInactiveCoverDismissesEditingAndConcealsPresentedContent() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        let anchor = PrivacyShieldAnchor(onBackground: {})
        controller.view.addSubview(anchor)
        window.layoutIfNeeded()
        NotificationCenter.default.post(name: UIScene.didActivateNotification, object: scene)
        let sheet = UIViewController()
        sheet.modalPresentationStyle = .pageSheet
        await withCheckedContinuation { continuation in
            controller.present(sheet, animated: false) { continuation.resume() }
        }
        defer {
            controller.dismiss(animated: false)
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }
        XCTAssertTrue(sheet.presentingViewController === controller)
        let field = UITextField(frame: CGRect(x: 24, y: 120, width: 200, height: 50))
        field.text = "123.45"
        sheet.view.addSubview(field)
        XCTAssertTrue(field.becomeFirstResponder())
        XCTAssertTrue(field.isFirstResponder)

        func pixels(_ color: UIColor) throws -> Data {
            sheet.view.backgroundColor = color
            window.layoutIfNeeded()
            return try XCTUnwrap(UIGraphicsImageRenderer(bounds: window.bounds).image { context in
                window.layer.render(in: context.cgContext)
            }.pngData())
        }
        XCTAssertNotEqual(try pixels(.red), try pixels(.blue))
        NotificationCenter.default.post(name: UIScene.willDeactivateNotification, object: scene)
        XCTAssertFalse(field.isFirstResponder, "editing must end before the inactive snapshot")
        XCTAssertEqual(try pixels(.red), try pixels(.blue), "presented content must be under the window cover")
        NotificationCenter.default.post(name: UIScene.didActivateNotification, object: scene)
        XCTAssertNotEqual(try pixels(.red), try pixels(.blue))
    }

    func testRootViewInstallsBackgroundHandlingWithoutFailingOnTemporaryInactivity() async throws {
        let star = FakeStar(phones: 1, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        await host.createRoom(label: "Room", size: 3, nickname: "Host")
        defer { host.leave() }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: RootView(coordinator: host, entitlement: FakeEntitlement(unlocked: false)))
        window.isHidden = false
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        NotificationCenter.default.post(name: UIScene.willDeactivateNotification, object: scene)
        XCTAssertEqual(Screen(host), .lobbyHost)
        NotificationCenter.default.post(name: UIScene.didEnterBackgroundNotification, object: scene)
        XCTAssertEqual(Screen(host), .interrupted)
        NotificationCenter.default.post(name: UIScene.didActivateNotification, object: scene)
        XCTAssertEqual(Screen(host), .interrupted, "foregrounding must not revive the room")
    }

    func testInactiveWindowHidesEveryPixelAndOnlyBackgroundEndsTheRound() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        var backgroundCount = 0
        let anchor = PrivacyShieldAnchor { backgroundCount += 1 }
        controller.view.addSubview(anchor)
        window.layoutIfNeeded()

        func notify(_ name: Notification.Name) {
            NotificationCenter.default.post(name: name, object: scene)
        }
        func pixels(_ color: UIColor) throws -> Data {
            controller.view.backgroundColor = color
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { context in
                window.layer.render(in: context.cgContext)
            }
            return try XCTUnwrap(image.pngData())
        }

        notify(UIScene.didActivateNotification)
        XCTAssertNotEqual(try pixels(.red), try pixels(.blue), "the active screen must render its content")
        notify(UIScene.willDeactivateNotification)
        XCTAssertEqual(backgroundCount, 0, "Control Center and permission prompts are not a background exit")
        XCTAssertEqual(try pixels(.red), try pixels(.blue), "no underlying pixel may enter the inactive snapshot")
        notify(UIScene.didEnterBackgroundNotification)
        XCTAssertEqual(backgroundCount, 1)
        XCTAssertEqual(try pixels(.red), try pixels(.blue))
        notify(UIScene.willEnterForegroundNotification)
        XCTAssertEqual(try pixels(.red), try pixels(.blue), "keep the cover until active, not merely foreground")
        notify(UIScene.didActivateNotification)
        XCTAssertNotEqual(try pixels(.red), try pixels(.blue))
    }
}
