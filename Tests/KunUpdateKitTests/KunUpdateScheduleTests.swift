import XCTest
@testable import KunUpdateKit

final class KunUpdateScheduleTests: XCTestCase {
    /// 定期チェックは6時間間隔（全アプリ共通の運用値。変更は kunkit で一元管理する）。
    func testCheckIntervalIsSixHours() {
        XCTAssertEqual(KunUpdateSchedule.checkInterval, 6 * 60 * 60)
        XCTAssertEqual(KunUpdateSchedule.checkIntervalTolerance, KunUpdateSchedule.checkInterval / 10)
    }
}
