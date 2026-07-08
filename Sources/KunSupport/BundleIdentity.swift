import Foundation

/// バンドル ID の基底名（ローカル検証ビルドの `.local` サフィックスを除いた ID）を扱う。
///
/// ローカル検証ビルド（`com.mtkg.<app>.local`）と本番（`com.mtkg.<app>`）を同一アプリとして
/// 扱いたい場面（自己更新の ID 検証・kuntraykun 連携・ローカル表示判定）で使う。
public enum BundleIdentity {
    private static let localSuffix = ".local"

    /// `.local` サフィックスを除いた基底バンドル ID。nil は nil のまま返す。
    public static func baseID(_ id: String?) -> String? {
        guard let id else { return nil }
        return id.hasSuffix(localSuffix) ? String(id.dropLast(localSuffix.count)) : id
    }

    /// ローカル検証ビルド（`.local` 終端）の ID かどうか。nil は false。
    public static func isLocal(_ id: String?) -> Bool {
        id?.hasSuffix(localSuffix) ?? false
    }

    /// 実行中アプリ（`Bundle.main`）がローカル検証ビルドかどうか。
    public static var isLocalBuild: Bool {
        isLocal(Bundle.main.bundleIdentifier)
    }
}
