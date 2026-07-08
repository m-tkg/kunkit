import Foundation

/// 連携プロトコル v4: kun アプリが共有ファイルへ書き出すメニュー構造のスナップショット。
///
/// 各 kun アプリは自分の `NSMenu` をこの形式の JSON にシリアライズして
/// `sharedMenuDirRelativePath` 配下の `<基底bundleID>.json` へ原子的に書き出し、
/// kuntraykun がそれを読んでサブメニューとして再構築する。
/// 前方互換のため未知キーは無視し、欠損キーは既定値で補完する。
public struct MenuSnapshot: Codable, Equatable {
    /// 現行のスナップショット形式バージョン。
    public static let currentFormatVersion = 1
    /// 許容するネストの最大深さ（トップレベル = 1）。超過分の children はデコード時に落とす。
    public static let maxDepth = 3
    /// 許容する項目数の上限（ツリー全体・深さ優先で数える）。超過分はデコード時に落とす。
    public static let maxItemCount = 500

    public var formatVersion: Int
    /// スナップショットの世代トークン。invoke 時に一致確認し、古い依頼の誤実行を防ぐ。
    public var generation: String
    public var items: [MenuItemNode]

    public init(formatVersion: Int = MenuSnapshot.currentFormatVersion,
                generation: String,
                items: [MenuItemNode]) {
        self.formatVersion = formatVersion
        self.generation = generation
        self.items = items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion)
            ?? MenuSnapshot.currentFormatVersion
        generation = try container.decodeIfPresent(String.self, forKey: .generation) ?? ""
        items = try container.decodeIfPresent([MenuItemNode].self, forKey: .items) ?? []
    }

    /// JSON へエンコードする（キー順固定で差分を安定させる）。
    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// JSON からデコードし、深さ・項目数の上限で切り詰める。
    public static func decode(_ data: Data) throws -> MenuSnapshot {
        var snapshot = try JSONDecoder().decode(MenuSnapshot.self, from: data)
        var budget = maxItemCount
        snapshot.items = truncate(snapshot.items, depth: 1, budget: &budget)
        return snapshot
    }

    /// ツリーを深さ優先で辿り、ID が一致する最初のノードを返す。
    public func findNode(id: String) -> MenuItemNode? {
        Self.findNode(id: id, in: items)
    }

    // MARK: インデックスパス ID

    /// インデックスパスを ID 文字列にする（例 `[0, 2, 1]` → `"0.2.1"`）。
    /// アプリが安定 ID を明示しない場合の既定の ID 形式。
    public static func indexPathID(_ path: [Int]) -> String {
        path.map(String.init).joined(separator: ".")
    }

    /// インデックスパス ID を解析する。非数値・負数・空要素を含むものは nil。
    public static func parseIndexPathID(_ id: String) -> [Int]? {
        guard !id.isEmpty else { return nil }
        var path: [Int] = []
        for part in id.split(separator: ".", omittingEmptySubsequences: false) {
            guard let index = Int(part), index >= 0 else { return nil }
            path.append(index)
        }
        return path
    }

    // MARK: private

    private static func findNode(id: String, in nodes: [MenuItemNode]) -> MenuItemNode? {
        for node in nodes {
            if node.id == id { return node }
            if let found = findNode(id: id, in: node.children) { return found }
        }
        return nil
    }

    private static func truncate(_ nodes: [MenuItemNode], depth: Int, budget: inout Int) -> [MenuItemNode] {
        var result: [MenuItemNode] = []
        for var node in nodes {
            guard budget > 0 else { break }
            budget -= 1
            node.children = depth >= maxDepth ? [] : truncate(node.children, depth: depth + 1, budget: &budget)
            result.append(node)
        }
        return result
    }
}

/// メニュー項目1つ分。サブメニューは `children` のネストで表す。
/// 画像・attributedTitle・keyEquivalent・カスタムビューは転送しない（v4 スコープ外）。
public struct MenuItemNode: Codable, Equatable {
    /// 項目 ID。既定はインデックスパス（`MenuSnapshot.indexPathID`）。アプリが安定 ID を明示してもよい。
    public var id: String
    public var title: String
    public var enabled: Bool
    public var state: MenuItemState
    public var separator: Bool
    public var children: [MenuItemNode]

    public init(id: String,
                title: String,
                enabled: Bool = true,
                state: MenuItemState = .off,
                separator: Bool = false,
                children: [MenuItemNode] = []) {
        self.id = id
        self.title = title
        self.enabled = enabled
        self.state = state
        self.separator = separator
        self.children = children
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        // 未知の state 値（将来の拡張）は off に落とす。
        let rawState = try container.decodeIfPresent(String.self, forKey: .state) ?? ""
        state = MenuItemState(rawValue: rawState) ?? .off
        separator = try container.decodeIfPresent(Bool.self, forKey: .separator) ?? false
        children = try container.decodeIfPresent([MenuItemNode].self, forKey: .children) ?? []
    }
}

/// メニュー項目のチェック状態（`NSControl.StateValue` 相当）。
public enum MenuItemState: String, Codable {
    case off
    case on
    case mixed
}
