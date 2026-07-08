import AppKit
import XCTest
@testable import KunIntegrationBridge
import KunIntegrationProtocol

/// メニューのシリアライズ（`makeSnapshot`）のテスト。
/// ファイル書き出し・分散通知を伴う `export(_:)` 本体はここでは扱わない。
@MainActor
final class KuntraykunMenuExportTests: XCTestCase {
    /// menuNeedsUpdate で項目を再構築する動的メニューのスタブ。
    private final class DynamicMenuDelegate: NSObject, NSMenuDelegate {
        var updateCount = 0
        func menuNeedsUpdate(_ menu: NSMenu) {
            updateCount += 1
            menu.removeAllItems()
            menu.addItem(withTitle: "動的項目1", action: nil, keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "動的項目2", action: nil, keyEquivalent: "")
        }
    }

    /// 動的メニュー（delegate が menuNeedsUpdate で構築）でも、シリアライズ前に
    /// delegate を明示的に呼んで最新内容を書き出せること。
    /// NSMenu.update() は menuNeedsUpdate を呼ばない（実機確認済み）ため、
    /// これを怠ると items が空になる（gitkun / whisperkun で実際に発生した不具合）。
    func testDynamicMenuIsPopulatedBeforeSerialization() {
        let delegate = DynamicMenuDelegate()
        let menu = NSMenu()
        menu.delegate = delegate

        let snapshot = KuntraykunMenuExport.makeSnapshot(of: menu, generation: "g")

        XCTAssertEqual(delegate.updateCount, 1, "シリアライズ前に menuNeedsUpdate が呼ばれる")
        XCTAssertEqual(snapshot.items.count, 3)
        XCTAssertEqual(snapshot.items[0].title, "動的項目1")
        XCTAssertTrue(snapshot.items[1].separator)
        XCTAssertEqual(snapshot.items[2].title, "動的項目2")
    }

    /// delegate の無い静的メニューは従来どおりそのまま書き出せること。
    func testStaticMenuSerializesAsIs() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(withTitle: "静的項目", action: nil, keyEquivalent: "")

        let snapshot = KuntraykunMenuExport.makeSnapshot(of: menu, generation: "g")

        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.items[0].title, "静的項目")
        XCTAssertEqual(snapshot.generation, "g")
    }
}
