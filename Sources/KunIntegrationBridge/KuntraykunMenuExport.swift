import AppKit
import OSLog
import KunIntegrationProtocol

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.mtkg.kun", category: "kuntraykun")

/// 自分のステータスメニューの構造を kuntraykun 用の共有場所に書き出す（連携プロトコル v4）。
///
/// kuntraykun は他プロセスの `NSMenu` を直接読めないため、メニュー構造を JSON で
/// `~/Library/Application Support/Kuntraykun/Menus/<基底bundleID>.json` へ原子的に書き出し、
/// `menuSnapshot` 分散通知で知らせる。kuntraykun はこれをサブメニューとして再構築し、
/// 項目クリックを `invokeMenuItem` で依頼してくる。
/// 仕様: kuntraykun リポジトリ `docs/kun-integration-protocol.md`（v4）。
///
/// 通常は `KuntraykunBridge` 経由（`exportMenuSnapshot()`）で使う。表示中メニューの
/// 保留制御は Bridge 側が担うため、これを直接呼ぶ場合はメニュー非表示時に呼ぶこと。
@MainActor
public enum KuntraykunMenuExport {
    /// 直近に書き出したスナップショットの世代。invokeMenuItem の世代確認に使う。
    public private(set) static var currentGeneration = ""

    /// `.local` を除いた基底 bundle ID。
    static var baseBundleID: String {
        IntegrationProtocol.baseBundleID(Bundle.main.bundleIdentifier ?? "")
    }

    private static var fileURL: URL? {
        guard let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            !baseBundleID.isEmpty else { return nil }
        return base
            .appendingPathComponent(IntegrationProtocol.sharedMenuDirRelativePath, isDirectory: true)
            .appendingPathComponent("\(baseBundleID).json")
    }

    /// 現在のメニュー構造を書き出し、`menuSnapshot` を通知する。
    public static func export(_ menu: NSMenu) {
        guard let fileURL else { return }
        menu.update() // enabled 状態を確定させてから読む。
        let generation = UUID().uuidString
        let snapshot = MenuSnapshot(generation: generation, items: nodes(of: menu, path: []))
        do {
            let data = try snapshot.encode()
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            // 原子的書き込み → 通知の順序（読み手が中途半端な内容を見ないため）。
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("menu snapshot export failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        currentGeneration = generation
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(IntegrationProtocol.menuSnapshotNotification), object: nil,
            userInfo: [
                IntegrationProtocol.keyBundleID: baseBundleID,
                IntegrationProtocol.keyGeneration: generation,
                IntegrationProtocol.keyProtocol: IntegrationProtocol.version,
            ],
            deliverImmediately: true
        )
    }

    /// インデックスパス ID（例 `"3"` / `"3.1"`）の項目を実行する。見つからなければ false。
    public static func performItem(id: String, in menu: NSMenu) -> Bool {
        guard let path = MenuSnapshot.parseIndexPathID(id), !path.isEmpty else { return false }
        var current = menu
        for index in path.dropLast() {
            guard index < current.numberOfItems,
                  let submenu = current.item(at: index)?.submenu else { return false }
            current = submenu
        }
        let last = path[path.count - 1]
        guard last < current.numberOfItems else { return false }
        current.performActionForItem(at: last)
        return true
    }

    // MARK: - private

    /// メニューを歩いてノード列にする。ID は実際の NSMenu 内インデックスのパス
    /// （非表示項目はスキップするが、ID の採番は実インデックスのまま。invoke 時にそのまま辿れる）。
    private static func nodes(of menu: NSMenu, path: [Int]) -> [MenuItemNode] {
        var result: [MenuItemNode] = []
        for (index, item) in menu.items.enumerated() {
            if item.isHidden { continue }
            let itemPath = path + [index]
            let id = MenuSnapshot.indexPathID(itemPath)
            if item.isSeparatorItem {
                result.append(MenuItemNode(id: id, title: "", enabled: false, separator: true))
                continue
            }
            // カスタムビュー項目は転送不能（v4 スコープ外）。タイトルのみ・操作不可で書き出す。
            if item.view != nil {
                result.append(MenuItemNode(id: id, title: item.title, enabled: false))
                continue
            }
            let children = item.submenu.map { nodes(of: $0, path: itemPath) } ?? []
            result.append(MenuItemNode(
                id: id,
                title: item.title,
                enabled: item.isEnabled,
                state: state(of: item),
                children: children
            ))
        }
        return result
    }

    private static func state(of item: NSMenuItem) -> MenuItemState {
        switch item.state {
        case .on: return .on
        case .mixed: return .mixed
        default: return .off
        }
    }
}
