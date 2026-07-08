import XCTest
@testable import KunSupport

final class BundleIdentityTests: XCTestCase {
    func testBaseIDStripsLocalSuffix() {
        XCTAssertEqual(BundleIdentity.baseID("com.mtkg.clipkun.local"), "com.mtkg.clipkun")
    }

    func testBaseIDLeavesProductionUnchanged() {
        XCTAssertEqual(BundleIdentity.baseID("com.mtkg.clipkun"), "com.mtkg.clipkun")
    }

    func testBaseIDPassesNilThrough() {
        XCTAssertNil(BundleIdentity.baseID(nil))
    }

    func testIsLocal() {
        XCTAssertTrue(BundleIdentity.isLocal("com.mtkg.clipkun.local"))
        XCTAssertFalse(BundleIdentity.isLocal("com.mtkg.clipkun"))
        XCTAssertFalse(BundleIdentity.isLocal(nil))
    }
}
