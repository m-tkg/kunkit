# kunkit — kun シリーズ共有ライブラリ

kun シリーズ（`com.mtkg.*kun` の macOS メニューバー常駐アプリ）と集約ハブ kuntraykun が共有する
実装を集約する SwiftPM ライブラリ。**kun アプリ側で複製されがちな共通機能はまずここに実装する**。

- kun アプリ共通ガイド: `../kun-template/CLAUDE_base.md`（canonical は kun-template リポジトリ）。
- 連携プロトコルの正式仕様: kuntraykun リポジトリ `docs/kun-integration-protocol.md`。

## ターゲット構成

| ターゲット | 依存 | 内容 |
|---|---|---|
| `KunIntegrationProtocol` | Foundation | 連携プロトコルの定数・`MenuSnapshot` モデル（ハブ／アプリ共通の定義） |
| `KunIntegrationBridge` | AppKit, ↑ | kun アプリ側の連携実装（`KuntraykunBridge` / `IconExport` / `MenuExport`） |
| `KunUpdateKit` | Foundation | 更新チェック（`GitHubReleaseFetcher` の ETag 取得 / `ReleaseInfo` / `VersionComparator` / `KunUpdateSchedule` / `ReleaseDownloader`） |
| `KunSupport` | Foundation | 汎用ユーティリティ（`BundleIdentity` / `ProcessRunner` / `KunSettingsStore`） |
| `KunAppKit` | AppKit, `KunSupport`, `KunUpdateKit` | メニューバーアプリ共通の AppKit 実装（`KunAppLaunch` / `LoginItemController` / `SelfUpdater`） |

各アプリは必要なプロダクトだけを `Package.swift` の依存に足す。

## 開発方針

- **TDD**: Foundation で完結する純粋ロジック（`KunSupport` / `KunUpdateKit` のモデル・比較・判定）は
  テスト先行。AppKit / プロセス / ネットワーク I/O 依存部（`KunAppKit`・`ReleaseDownloader`）は
  各アプリのローカルビルドで手動確認する。
- **アプリ固有を持ち込まない**: 文言・アプリ名・bundle ID・リポジトリ名は**注入**する
  （例: `LoginItemController(requiresApprovalMessage:)`、`SelfUpdater(appName:)`、
  `GitHubReleaseFetcher(repoFullName:userAgent:)`）。ローカライズ表（`*.lproj`）はライブラリに置かない。
- **swift-tools 5.9 / macOS 13** を維持する（whisperkun の Swift 6 / macOS 26 からも下位互換で使える）。
  並行コードは Swift 6 でも警告が出ない形にする（`ProcessRunner` の `OutputBox` 参照型アキュムレータ等）。
- ロガーの subsystem は `Bundle.main.bundleIdentifier`（利用側アプリの ID）にフォールバックさせる。

## リリースと利用側の追従

- 変更は PR 経由。マージ後 `git tag -a vX.Y.Z` を push（このリポジトリに release ワークフローは無く、
  タグは semver の目印。SwiftPM は git タグで解決する）。
- **後方互換な追加はマイナー、破壊的変更はメジャー**。各アプリは `Package.swift` の
  `.package(url:from:)` と `swift package update kunkit` で追従する
  （`Package.resolved` を追跡するリポジトリは resolved の変更もコミット）。
- 破壊的変更をするときは、利用側 7 アプリ＋テンプレート（kun-template）の追従 PR まで含めて計画する。

## ブランチ運用

- `main` へ直接コミットしない。変更は PR 経由。作業ブランチは最新 `main` から切る。
