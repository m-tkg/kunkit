# kunkit

kun シリーズ（`com.mtkg.*kun` の macOS メニューバー常駐アプリ群）と集約ハブ
[kuntraykun](https://github.com/m-tkg/kuntraykun) の連携プロトコル実装を共有するライブラリ。

正式仕様は kuntraykun リポジトリの `docs/kun-integration-protocol.md`（連携プロトコル v1〜v4）。

## ターゲット

- **KunIntegrationProtocol**（Foundation のみ）
  - `IntegrationProtocol`: 通知名・userInfo キー・共有ディレクトリ・基底 bundleID などの定数とヘルパー
  - `MenuSnapshot` / `MenuItemNode`: v4（サブメニュー表示）のメニュー構造モデルとシリアライズ規則
  - kuntraykun 本体（ハブ側）と各 kun アプリの両方が参照する
- **KunIntegrationBridge**（AppKit、kun アプリ側の実装本体）
  - `KuntraykunBridge`: sync / showMenu / requestMenu / invokeMenuItem の観測、アイコン表示制御、
    アップデート報告、メニュー表示中の書き出し保留
  - `KuntraykunIconExport`: 実アイコンの共有書き出し（v2）
  - `KuntraykunMenuExport`: メニュー構造の共有書き出しと項目実行（v4）

## 使い方（kun アプリ側）

```swift
// Package.swift
.package(url: "https://github.com/m-tkg/kunkit.git", from: "1.0.0"),
// executableTarget の dependencies に
.product(name: "KunIntegrationBridge", package: "kunkit"),
```

```swift
import KunIntegrationBridge

// AppDelegate の起動処理（statusItem と menu は自分のステータスバー実装のもの）
let bridge = KuntraykunBridge(statusItem: statusItem, menu: menu)
bridge.start() // 観測開始・appLaunched 送信・初回メニュー書き出しまで行う
kuntraykunBridge = bridge

// アップデート有無が変わったら
kuntraykunBridge?.reportUpdate(hasUpdate)
// メニュー文言・チェック状態が変わったら（表示中は自動で保留される）
kuntraykunBridge?.exportMenuSnapshot()
```

特殊な配線が必要なアプリは、クロージャ版の
`init(setHidden:popUpMenu:exportMenu:performMenuItem:trackingMenu:)` を使う。

## バージョニング

semver。プロトコルの後方互換な追加はマイナー、破壊的変更はメジャーを上げる。
