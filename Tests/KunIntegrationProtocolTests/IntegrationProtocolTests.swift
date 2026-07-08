import XCTest
@testable import KunIntegrationProtocol

final class IntegrationProtocolTests: XCTestCase {
    func testEncodeManagedSortsAndDedupes() {
        let s = IntegrationProtocol.encodeManaged(
            ["com.mtkg.keykun", "com.mtkg.clipkun", "com.mtkg.keykun"])
        XCTAssertEqual(s, "com.mtkg.clipkun,com.mtkg.keykun")
    }

    func testEncodeEmpty() {
        XCTAssertEqual(IntegrationProtocol.encodeManaged([String]()), "")
    }

    func testDecodeManaged() {
        XCTAssertEqual(
            IntegrationProtocol.decodeManaged("com.mtkg.clipkun,com.mtkg.keykun"),
            ["com.mtkg.clipkun", "com.mtkg.keykun"])
    }

    func testDecodeTrimsAndDropsEmpty() {
        XCTAssertEqual(
            IntegrationProtocol.decodeManaged(" com.mtkg.clipkun , , com.mtkg.keykun "),
            ["com.mtkg.clipkun", "com.mtkg.keykun"])
        XCTAssertEqual(IntegrationProtocol.decodeManaged(""), [])
    }

    func testEncodeDecodeRoundTrip() {
        let ids = ["com.mtkg.keykun", "com.mtkg.clipkun"]
        let decoded = IntegrationProtocol.decodeManaged(IntegrationProtocol.encodeManaged(ids))
        XCTAssertEqual(decoded, ids.sorted())
    }

    func testBaseBundleIDStripsLocal() {
        XCTAssertEqual(IntegrationProtocol.baseBundleID("com.mtkg.clipkun.local"), "com.mtkg.clipkun")
        XCTAssertEqual(IntegrationProtocol.baseBundleID("com.mtkg.clipkun"), "com.mtkg.clipkun")
    }
}
