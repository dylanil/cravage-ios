import XCTest
@testable import CravageCore

final class PlaceholderTests: XCTestCase {
    func testPackageBuildsAndProtocolVersionIsTwo() {
        XCTAssertEqual(CravageCore.protocolVersion, 3, "3 since roomcode_dispute joined the action set (2026-10-04); 2 was the sealed room code")
    }
}
