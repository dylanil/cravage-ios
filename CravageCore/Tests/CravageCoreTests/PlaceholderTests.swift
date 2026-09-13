import XCTest
@testable import CravageCore

final class PlaceholderTests: XCTestCase {
    func testPackageBuildsAndProtocolVersionIsOne() {
        XCTAssertEqual(CravageCore.protocolVersion, 1)
    }
}
