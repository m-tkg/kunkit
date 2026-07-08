// swift-tools-version: 5.9
import PackageDescription

// kun シリーズ（com.mtkg.*kun のメニューバー常駐アプリ群）と集約ハブ kuntraykun の共有ライブラリ。
// - KunIntegrationProtocol: 連携プロトコルの定数と MenuSnapshot モデル（Foundation のみ）。ハブとアプリ双方が参照。
// - KunIntegrationBridge: 各 kun アプリ側の連携実装（AppKit）。KuntraykunBridge / IconExport / MenuExport。
// - KunUpdateKit: GitHub Releases の更新チェック共通部（ETag 取得・モデル・比較・スケジュール・zip DL）。Foundation。
// - KunSupport: プラットフォーム非依存の共通ユーティリティ（基底 bundleID・プロセス実行・設定永続化）。Foundation。
// - KunAppKit: メニューバーアプリ共通の AppKit 実装（多重起動防止・ログイン項目・自己更新）。AppKit。
let package = Package(
    name: "kunkit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "KunIntegrationProtocol", targets: ["KunIntegrationProtocol"]),
        .library(name: "KunIntegrationBridge", targets: ["KunIntegrationBridge"]),
        .library(name: "KunUpdateKit", targets: ["KunUpdateKit"]),
        .library(name: "KunSupport", targets: ["KunSupport"]),
        .library(name: "KunAppKit", targets: ["KunAppKit"]),
    ],
    targets: [
        .target(name: "KunIntegrationProtocol"),
        .target(name: "KunIntegrationBridge", dependencies: ["KunIntegrationProtocol"]),
        .target(name: "KunUpdateKit"),
        // プラットフォーム非依存の共通ユーティリティ。
        .target(name: "KunSupport"),
        // メニューバーアプリ共通の AppKit 実装（自己更新は KunSupport / KunUpdateKit に依存）。
        .target(name: "KunAppKit", dependencies: ["KunSupport", "KunUpdateKit"]),
        .testTarget(name: "KunIntegrationProtocolTests", dependencies: ["KunIntegrationProtocol"]),
        .testTarget(name: "KunIntegrationBridgeTests", dependencies: ["KunIntegrationBridge"]),
        .testTarget(name: "KunUpdateKitTests", dependencies: ["KunUpdateKit"]),
        .testTarget(name: "KunSupportTests", dependencies: ["KunSupport"]),
    ]
)
