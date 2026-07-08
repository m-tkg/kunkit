import XCTest
@testable import KunSupport

final class KunSettingsStoreTests: XCTestCase {
    private struct Sample: Codable, Equatable {
        var name: String
        var count: Int

        init(name: String, count: Int) {
            self.name = name
            self.count = count
        }

        // 欠損キーは既定値で補完（前方/後方互換）。
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? "default"
            count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        }
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("KunSettingsStoreTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    func testSaveAndLoadRoundTrip() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = KunSettingsStore(url: url, defaultValue: Sample(name: "default", count: 0))

        try store.save(Sample(name: "hello", count: 3))
        XCTAssertEqual(store.load(), Sample(name: "hello", count: 3))
    }

    func testLoadMissingFileReturnsDefault() {
        let store = KunSettingsStore(url: tempURL(), defaultValue: Sample(name: "fallback", count: 9))
        XCTAssertEqual(store.load(), Sample(name: "fallback", count: 9))
    }

    func testLoadCorruptFileReturnsDefault() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let store = KunSettingsStore(url: url, defaultValue: Sample(name: "fallback", count: 9))
        XCTAssertEqual(store.load(), Sample(name: "fallback", count: 9))
    }

    func testLoadPartialJSONFillsMissingKeys() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"name":"partial"}"#.utf8).write(to: url)
        let store = KunSettingsStore(url: url, defaultValue: Sample(name: "default", count: 0))
        XCTAssertEqual(store.load(), Sample(name: "partial", count: 0))
    }

    func testDefaultURLShape() {
        let url = KunSettingsStore<Sample>.defaultURL(appFolderName: "Newkun")
        XCTAssertEqual(url.lastPathComponent, "settings.json")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "Newkun")
    }
}
