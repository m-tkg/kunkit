import XCTest
@testable import KunUpdateKit

final class VersionComparatorTests: XCTestCase {
    func testNewerPatch() {
        XCTAssertTrue(VersionComparator.isNewer(tag: "v1.0.1", than: "1.0.0"))
    }

    func testNotNewerWhenEqual() {
        XCTAssertFalse(VersionComparator.isNewer(tag: "v1.2.3", than: "1.2.3"))
    }

    func testOlderIsNotNewer() {
        XCTAssertFalse(VersionComparator.isNewer(tag: "v1.0.0", than: "1.1.0"))
    }

    func testHandlesMissingComponents() {
        XCTAssertTrue(VersionComparator.isNewer(tag: "v2", than: "1.9.9"))
        XCTAssertFalse(VersionComparator.isNewer(tag: "v1", than: "1.0.0"))
    }

    func testIgnoresVPrefixAndSuffix() {
        XCTAssertTrue(VersionComparator.isNewer(tag: "V1.2.0", than: "1.1.0"))
        XCTAssertFalse(VersionComparator.isNewer(tag: "1.0.0-beta", than: "1.0.0"))
    }
}
