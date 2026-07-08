import AppKit
import OSLog
import KunIntegrationProtocol

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.mtkg.kun", category: "kuntraykun")

/// kuntraykun（`com.mtkg.kuntraykun`）に「まとめられる」ための連携ブリッジ（kun アプリ側）。
///
/// 仕様: kuntraykun リポジトリの `docs/kun-integration-protocol.md`（連携プロトコル v1〜v4）。
///
/// 役割:
/// - `sync` を観測し、自分が管理対象なら（かつ kuntraykun 起動中なら）自分のアイコンを隠す（v1）。
/// - `showMenu` を観測し、自分宛なら指定座標に自分のメニューを popUp する（v1）。
/// - 起動時に `appLaunched` を送り、kuntraykun から最新の `sync` を受け取る（v1）。
/// - `reportUpdate(_:)` で「アップデートあり/なし」を kuntraykun に集約表示させる（v3）。
/// - `requestMenu` / `invokeMenuItem` を観測し、メニュー構造の書き出しと項目実行に応じる（v4）。
///
/// 典型的な使い方は `init(statusItem:menu:)`（隠す・popUp・書き出し・実行を既定実装で配線）。
/// 特殊な配線が必要なアプリはクロージャ版の init を使う。
/// v4 の「メニュー表示中はスナップショット書き出しを保留する」制御
/// （表示中の `menu.update()` は `menuNeedsUpdate` 再構築で開いているメニューを壊す）は
/// `trackingMenu` のトラッキング通知を観測して本クラスが自動で行う。
@MainActor
public final class KuntraykunBridge {
    /// kuntraykun 本体（本番／ローカル検証ビルドの両方を起動中判定の対象にする）。
    private static let kuntraykunBundleIDs = [
        IntegrationProtocol.kuntraykunBundleID,
        IntegrationProtocol.kuntraykunBundleID + ".local",
    ]
    /// 管理対象フラグの永続化キー（全 kun アプリ共通）。
    private static let managedDefaultsKey = "KuntraykunManaged"

    /// 自分のアイコンを隠す/戻すクロージャ。
    private let setHidden: (Bool) -> Void
    /// 自分のメニューを指定座標に出すクロージャ。
    private let popUpMenu: (NSPoint) -> Void
    /// メニュースナップショットを書き出すクロージャ（連携 v4）。
    private let exportMenu: () -> Void
    /// サブメニュー項目の実行クロージャ（連携 v4、項目 ID → 実行成否）。
    private let performMenuItem: (String) -> Bool
    /// 表示中保留の観測対象メニュー（nil なら保留制御なし＝静的メニュー向け）。
    private let trackingMenu: NSMenu?

    /// `.local` を除いた自分の基底 bundle ID。
    private let myBundleID: String
    /// kuntraykun の管理対象に選ばれているか（UserDefaults に永続化）。
    private var isManaged: Bool
    /// 遅延表示（復活）の世代。再評価のたびに進めて保留中の復活をキャンセルする。
    private var showGeneration = 0
    /// 直近に kuntraykun へ報告したアップデート有無。sync 受信時に再送して整合させる。
    private var lastReportedUpdate = false
    /// `NSWorkspace.runningApplications` の KVO 監視トークン。
    private var runningAppsObservation: NSKeyValueObservation?
    /// 自分のメニューが表示（トラッキング）中か。
    private var isMenuOpen = false
    /// 表示中に書き出し要求が来たら保留し、閉じたあとに書き出す。
    private var menuExportPending = false
    private var trackingObservers: [NSObjectProtocol] = []

    /// クロージャ版 init。配線を細かく制御したいアプリ向け。
    /// - Parameter trackingMenu: 表示中保留の観測対象。動的メニュー
    ///   （`menuNeedsUpdate` で再構築するアプリ）は必ず自分のステータスメニューを渡すこと。
    public init(setHidden: @escaping (Bool) -> Void,
                popUpMenu: @escaping (NSPoint) -> Void,
                exportMenu: @escaping () -> Void,
                performMenuItem: @escaping (String) -> Bool,
                trackingMenu: NSMenu? = nil) {
        self.setHidden = setHidden
        self.popUpMenu = popUpMenu
        self.exportMenu = exportMenu
        self.performMenuItem = performMenuItem
        self.trackingMenu = trackingMenu
        self.myBundleID = IntegrationProtocol.baseBundleID(Bundle.main.bundleIdentifier ?? "")
        self.isManaged = UserDefaults.standard.bool(forKey: Self.managedDefaultsKey)
    }

    /// 標準配線の init。ほとんどの kun アプリはこれで足りる。
    /// 隠す = `statusItem.isVisible`、popUp = activate + `menu.popUp`、
    /// 書き出し/実行 = `KuntraykunMenuExport`、表示中保留 = `menu` を観測。
    public convenience init(statusItem: NSStatusItem, menu: NSMenu) {
        self.init(
            setHidden: { statusItem.isVisible = !$0 },
            popUpMenu: { point in
                // 非アクティブ（LSUIElement）のままだと popUp が表示に失敗することがある。
                NSApp.activate(ignoringOtherApps: true)
                menu.popUp(positioning: nil, at: point, in: nil)
            },
            exportMenu: { KuntraykunMenuExport.export(menu) },
            performMenuItem: { KuntraykunMenuExport.performItem(id: $0, in: menu) },
            trackingMenu: menu
        )
    }

    /// 観測を開始し、初期のアイコン表示を決め、起動を通知し、初回のメニュー書き出しを行う。
    public func start() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(onSync(_:)),
                        name: Notification.Name(IntegrationProtocol.syncNotification), object: nil)
        dnc.addObserver(self, selector: #selector(onShowMenu(_:)),
                        name: Notification.Name(IntegrationProtocol.showMenuNotification), object: nil)
        dnc.addObserver(self, selector: #selector(onRequestMenu(_:)),
                        name: Notification.Name(IntegrationProtocol.requestMenuNotification), object: nil)
        dnc.addObserver(self, selector: #selector(onInvokeMenuItem(_:)),
                        name: Notification.Name(IntegrationProtocol.invokeMenuItemNotification), object: nil)

        // kuntraykun の起動/終了でアイコン表示を再計算する。
        // LSUIElement（メニューバー常駐）アプリの起動/終了は NSWorkspace の didLaunch/didTerminate 通知が
        // 配信されないため、runningApplications を KVO 監視する（kuntraykun のクラッシュ時もアイコンが復活する）。
        // .initial で初回の表示判定も行う。
        runningAppsObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.initial]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshVisibility() }
        }

        // 表示中保留: 自分のメニューのトラッキング開始/終了を観測する（v4）。
        if let menu = trackingMenu {
            let center = NotificationCenter.default
            trackingObservers.append(center.addObserver(
                forName: NSMenu.didBeginTrackingNotification, object: menu, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.isMenuOpen = true }
            })
            trackingObservers.append(center.addObserver(
                forName: NSMenu.didEndTrackingNotification, object: menu, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.menuDidEndTracking() }
            })
        }

        // 起動を通知（kuntraykun が最新 sync を返してくれる）。
        dnc.postNotificationName(
            Notification.Name(IntegrationProtocol.appLaunchedNotification), object: nil,
            userInfo: [
                IntegrationProtocol.keyBundleID: myBundleID,
                IntegrationProtocol.keyProtocol: IntegrationProtocol.version,
            ],
            deliverImmediately: true
        )

        // 起動時に現在のメニュー構造を書き出しておく（kuntraykun 起動済みでもすぐサブメニューが出せる）。
        exportMenuSnapshot()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        for observer in trackingObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        runningAppsObservation?.invalidate()
    }

    // MARK: - 公開 API

    /// 「アップデートあり/なし」を kuntraykun に報告する（更新検知時・解消時に呼ぶ）（v3）。
    public func reportUpdate(_ hasUpdate: Bool) {
        lastReportedUpdate = hasUpdate
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(IntegrationProtocol.updateStateNotification), object: nil,
            userInfo: [
                IntegrationProtocol.keyBundleID: myBundleID,
                IntegrationProtocol.keyHasUpdate: hasUpdate ? "1" : "0",
                IntegrationProtocol.keyProtocol: IntegrationProtocol.version,
            ],
            deliverImmediately: true
        )
    }

    /// メニュー構造を書き出す（連携 v4）。メニュー内容が変わる箇所（文言・チェック状態の変化）から呼ぶ。
    /// 自分のメニューが表示中なら保留し、閉じたあとに書き出す。
    public func exportMenuSnapshot() {
        if isMenuOpen {
            menuExportPending = true
        } else {
            exportMenu()
        }
    }

    // MARK: - 通知ハンドラ

    /// 対象集合の通知。自分が含まれるかで管理対象フラグを更新・永続化し、アイコン表示を再計算する。
    @objc private func onSync(_ note: Notification) {
        let managed = IntegrationProtocol.decodeManaged(
            note.userInfo?[IntegrationProtocol.keyManaged] as? String ?? "")
        let nowManaged = managed.contains(myBundleID)
        if nowManaged != isManaged {
            isManaged = nowManaged
            UserDefaults.standard.set(nowManaged, forKey: Self.managedDefaultsKey)
            log.info("managed=\(nowManaged, privacy: .public)")
        }
        refreshVisibility()
        // 起動直後の kuntraykun にも現在のアップデート状態を伝える。
        reportUpdate(lastReportedUpdate)
    }

    /// メニュー表示依頼。自分宛なら指定スクリーン座標に自分のメニューを出す。
    @objc private func onShowMenu(_ note: Notification) {
        guard note.userInfo?[IntegrationProtocol.keyTarget] as? String == myBundleID,
              let xs = note.userInfo?[IntegrationProtocol.keyX] as? String, let x = Double(xs),
              let ys = note.userInfo?[IntegrationProtocol.keyY] as? String, let y = Double(ys) else { return }
        popUpMenu(NSPoint(x: x, y: y))
    }

    /// メニュースナップショットの書き出し依頼（連携 v4）。targets に自分が含まれるときだけ応じる。
    @objc private func onRequestMenu(_ note: Notification) {
        let targets = IntegrationProtocol.decodeManaged(
            note.userInfo?[IntegrationProtocol.keyTargets] as? String ?? "")
        guard targets.contains(myBundleID) else { return }
        exportMenuSnapshot()
    }

    /// サブメニュー項目の実行依頼（連携 v4）。世代が現行スナップショットと一致するときだけ実行する。
    /// 不一致（依頼が古い）なら実行せず、最新のスナップショットを書き出し直して知らせる。
    @objc private func onInvokeMenuItem(_ note: Notification) {
        guard note.userInfo?[IntegrationProtocol.keyTarget] as? String == myBundleID,
              let itemID = note.userInfo?[IntegrationProtocol.keyItemID] as? String else { return }
        let generation = note.userInfo?[IntegrationProtocol.keyGeneration] as? String ?? ""
        guard generation == KuntraykunMenuExport.currentGeneration else {
            log.info("invoke ignored (stale generation); re-exporting menu")
            exportMenuSnapshot()
            return
        }
        if !performMenuItem(itemID) {
            log.error("invoke failed: item \(itemID, privacy: .public) not found")
        }
        // 実行でメニュー内容（チェック状態や文言）が変わりうるので書き出し直す。
        // アクションの副作用（ウィンドウ表示等）が済んでから読むため、次のループに逃がす。
        DispatchQueue.main.async { [weak self] in self?.exportMenuSnapshot() }
    }

    // MARK: - private

    /// トラッキング終了。保留中の書き出しがあれば、AppKit の後処理が済む次のループで書き出す。
    private func menuDidEndTracking() {
        isMenuOpen = false
        guard menuExportPending else { return }
        menuExportPending = false
        DispatchQueue.main.async { [weak self] in self?.exportMenuSnapshot() }
    }

    /// アイコン表示規則: 隠す = (管理対象) かつ (kuntraykun 起動中)。
    /// kuntraykun が未起動なら隠さない（操作不能を防ぐフォールバック）。
    private func refreshVisibility() {
        // NSRunningApplication.runningApplications(withBundleIdentifier:) は実行中でも空を返すことがあり
        // （誤判定でアイコンが再表示される）、KVO 対象の NSWorkspace.shared.runningApplications と
        // 同じソースで判定して整合させる。
        let hubRunning = NSWorkspace.shared.runningApplications.contains { app in
            guard let id = app.bundleIdentifier else { return false }
            return Self.kuntraykunBundleIDs.contains(id)
        }
        // 再評価のたびに世代を進め、保留中の遅延表示を無効化する。
        showGeneration &+= 1
        if !isManaged || hubRunning {
            // 管理対象でない→表示、管理対象かつ kuntraykun 起動中→隠す（いずれも即時）。
            setHidden(isManaged && hubRunning)
        } else {
            // 管理対象だが kuntraykun を検知できない。KVO の瞬間的なゆらぎで誤って復活し
            // アイコンが一瞬出てしまうのを防ぐため、少し待ってから復活する（待機中に再検知したらキャンセル）。
            let gen = showGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.showGeneration == gen else { return }
                    self.setHidden(false)
                }
            }
        }
    }
}
