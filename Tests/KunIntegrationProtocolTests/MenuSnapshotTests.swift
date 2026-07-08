import XCTest
@testable import KunIntegrationProtocol

final class MenuSnapshotTests: XCTestCase {
    // MARK: エンコード/デコードのラウンドトリップ

    func testEncodeDecodeRoundTrip() throws {
        let snapshot = MenuSnapshot(
            generation: "gen-1",
            items: [
                MenuItemNode(id: "0", title: "Clipkun 1.2.3", enabled: false),
                MenuItemNode(id: "1", title: "", separator: true),
                MenuItemNode(id: "2", title: "設定…"),
                MenuItemNode(id: "3", title: "モード", children: [
                    MenuItemNode(id: "3.0", title: "オン", state: .on),
                    MenuItemNode(id: "3.1", title: "一部", state: .mixed),
                    MenuItemNode(id: "3.2", title: "オフ", state: .off),
                ]),
            ]
        )
        let decoded = try MenuSnapshot.decode(snapshot.encode())
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.formatVersion, MenuSnapshot.currentFormatVersion)
    }

    // MARK: 前方/後方互換

    func testDecodeFillsMissingKeysWithDefaults() throws {
        // id と title だけの最小 JSON。欠損キーは既定値で補完される。
        let json = """
        { "items": [ { "id": "0", "title": "設定…" } ] }
        """
        let snapshot = try MenuSnapshot.decode(Data(json.utf8))
        XCTAssertEqual(snapshot.formatVersion, 1)
        XCTAssertEqual(snapshot.generation, "")
        let item = try XCTUnwrap(snapshot.items.first)
        XCTAssertEqual(item.id, "0")
        XCTAssertEqual(item.title, "設定…")
        XCTAssertTrue(item.enabled)
        XCTAssertEqual(item.state, .off)
        XCTAssertFalse(item.separator)
        XCTAssertTrue(item.children.isEmpty)
    }

    func testDecodeIgnoresUnknownKeys() throws {
        let json = """
        { "formatVersion": 1, "generation": "g", "futureKey": true,
          "items": [ { "id": "0", "title": "A", "futureItemKey": "x" } ] }
        """
        let snapshot = try MenuSnapshot.decode(Data(json.utf8))
        XCTAssertEqual(snapshot.items.count, 1)
    }

    func testDecodeUnknownStateFallsBackToOff() throws {
        let json = """
        { "items": [ { "id": "0", "title": "A", "state": "future-state" } ] }
        """
        let snapshot = try MenuSnapshot.decode(Data(json.utf8))
        XCTAssertEqual(snapshot.items.first?.state, .off)
    }

    // MARK: 検証（切り詰め）

    func testDecodeTruncatesBeyondMaxDepth() throws {
        // 深さ maxDepth(3) を超える children はデコード時に落とす。
        var node = MenuItemNode(id: "d4", title: "深さ4")
        node = MenuItemNode(id: "d3", title: "深さ3", children: [node])
        node = MenuItemNode(id: "d2", title: "深さ2", children: [node])
        node = MenuItemNode(id: "d1", title: "深さ1", children: [node])
        let snapshot = MenuSnapshot(generation: "g", items: [node])

        let decoded = try MenuSnapshot.decode(snapshot.encode())
        let depth3 = decoded.items[0].children[0].children[0]
        XCTAssertEqual(depth3.id, "d3")
        XCTAssertTrue(depth3.children.isEmpty, "深さ4以降は切り詰められる")
    }

    func testDecodeTruncatesBeyondMaxItemCount() throws {
        let items = (0..<(MenuSnapshot.maxItemCount + 100)).map {
            MenuItemNode(id: "\($0)", title: "項目\($0)")
        }
        let snapshot = MenuSnapshot(generation: "g", items: items)
        let decoded = try MenuSnapshot.decode(snapshot.encode())
        XCTAssertEqual(decoded.items.count, MenuSnapshot.maxItemCount)
        XCTAssertEqual(decoded.items.last?.id, "\(MenuSnapshot.maxItemCount - 1)")
    }

    func testDecodeCountsNestedItemsTowardLimit() throws {
        // 項目数の上限はツリー全体（children 含む）で数える。
        let children = (0..<MenuSnapshot.maxItemCount).map {
            MenuItemNode(id: "c\($0)", title: "子\($0)")
        }
        let snapshot = MenuSnapshot(generation: "g", items: [
            MenuItemNode(id: "0", title: "親", children: children),
            MenuItemNode(id: "1", title: "あふれる項目"),
        ])
        let decoded = try MenuSnapshot.decode(snapshot.encode())
        let total = decoded.items.reduce(0) { $0 + 1 + $1.children.count }
        XCTAssertEqual(total, MenuSnapshot.maxItemCount)
        XCTAssertEqual(decoded.items.count, 1, "上限到達後のトップレベル項目は落ちる")
    }

    func testDecodeRejectsInvalidJSON() {
        XCTAssertThrowsError(try MenuSnapshot.decode(Data("not json".utf8)))
    }

    // MARK: インデックスパス ID

    func testIndexPathIDFormatting() {
        XCTAssertEqual(MenuSnapshot.indexPathID([0]), "0")
        XCTAssertEqual(MenuSnapshot.indexPathID([0, 2, 1]), "0.2.1")
    }

    func testParseIndexPathID() {
        XCTAssertEqual(MenuSnapshot.parseIndexPathID("0"), [0])
        XCTAssertEqual(MenuSnapshot.parseIndexPathID("0.2.1"), [0, 2, 1])
        XCTAssertNil(MenuSnapshot.parseIndexPathID(""))
        XCTAssertNil(MenuSnapshot.parseIndexPathID("a.b"))
        XCTAssertNil(MenuSnapshot.parseIndexPathID("1..2"))
        XCTAssertNil(MenuSnapshot.parseIndexPathID("-1"))
    }

    // MARK: findNode

    func testFindNodeByID() {
        let snapshot = MenuSnapshot(generation: "g", items: [
            MenuItemNode(id: "0", title: "A"),
            MenuItemNode(id: "1", title: "B", children: [
                MenuItemNode(id: "custom-id", title: "ネスト"),
            ]),
        ])
        XCTAssertEqual(snapshot.findNode(id: "0")?.title, "A")
        XCTAssertEqual(snapshot.findNode(id: "custom-id")?.title, "ネスト")
        XCTAssertNil(snapshot.findNode(id: "missing"))
    }

    // MARK: プロトコル定数（v4）

    func testProtocolV4Constants() {
        XCTAssertEqual(IntegrationProtocol.requestMenuNotification, "com.mtkg.kuntraykun.requestMenu")
        XCTAssertEqual(IntegrationProtocol.menuSnapshotNotification, "com.mtkg.kun.menuSnapshot")
        XCTAssertEqual(IntegrationProtocol.invokeMenuItemNotification, "com.mtkg.kuntraykun.invokeMenuItem")
        XCTAssertEqual(IntegrationProtocol.keyTargets, "targets")
        XCTAssertEqual(IntegrationProtocol.keyGeneration, "generation")
        XCTAssertEqual(IntegrationProtocol.keyItemID, "itemID")
        XCTAssertEqual(IntegrationProtocol.sharedMenuDirRelativePath, "Kuntraykun/Menus")
    }
}
