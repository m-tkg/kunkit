// swift-tools-version: 5.9
import PackageDescription

// kun シリーズ（com.mtkg.*kun のメニューバー常駐アプリ群）と集約ハブ kuntraykun の
// 連携プロトコル実装を共有するライブラリ。
// - KunIntegrationProtocol: 通知名・キー・基底IDなどの定数と MenuSnapshot モデル（Foundation のみ）。
//   kuntraykun 本体（ハブ側）と各 kun アプリの両方が参照する。
// - KunIntegrationBridge: 各 kun アプリ側の実装本体（AppKit）。
//   KuntraykunBridge / KuntraykunIconExport / KuntraykunMenuExport。
let package = Package(
    name: "kunkit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "KunIntegrationProtocol", targets: ["KunIntegrationProtocol"]),
        .library(name: "KunIntegrationBridge", targets: ["KunIntegrationBridge"]),
    ],
    targets: [
        .target(name: "KunIntegrationProtocol"),
        .target(name: "KunIntegrationBridge", dependencies: ["KunIntegrationProtocol"]),
        .testTarget(name: "KunIntegrationProtocolTests", dependencies: ["KunIntegrationProtocol"]),
    ]
)
