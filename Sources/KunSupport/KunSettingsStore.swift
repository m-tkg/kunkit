import Foundation

/// 設定値の JSON 永続化（`~/Library/Application Support/<appFolderName>/settings.json`）。
///
/// 読み込み失敗時は既定値にフォールバックする（壊れた設定でアプリを起動不能にしない）。
/// `Settings` 型はアプリごとに異なるためジェネリックにし、`decodeIfPresent ?? 既定値` の
/// 前方/後方互換デコードは `Settings` 側の `Decodable` 実装が担う。
public struct KunSettingsStore<Settings: Codable> {
    private let url: URL
    private let defaultValue: Settings

    /// - Parameters:
    ///   - url: 保存先ファイル。既定は `defaultURL(appFolderName:)`。
    ///   - defaultValue: 読み込み失敗・ファイル不在時に返す既定設定。
    public init(url: URL, defaultValue: Settings) {
        self.url = url
        self.defaultValue = defaultValue
    }

    /// 既定の保存先（`~/Library/Application Support/<appFolderName>/settings.json`）。
    public static func defaultURL(appFolderName: String) -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent(appFolderName, isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    /// 設定を読み込む。ファイルが無い/壊れている場合は既定値。
    public func load() -> Settings {
        guard let data = try? Data(contentsOf: url) else { return defaultValue }
        return (try? JSONDecoder().decode(Settings.self, from: data)) ?? defaultValue
    }

    /// 設定を保存する（親ディレクトリは必要に応じて作成、原子的書き込み）。
    public func save(_ settings: Settings) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: url, options: .atomic)
    }
}
