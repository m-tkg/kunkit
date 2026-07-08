import Foundation

/// リリースの zip アセットをダウンロードする共通実装。
public struct ReleaseDownloader {
    /// zip ダウンロードの失敗。
    public enum DownloadError: LocalizedError {
        /// リリースに `.zip` アセットが無い。
        case noZipAsset
        /// ダウンロードの HTTP ステータスが 2xx 以外。
        case httpError(status: Int)

        public var errorDescription: String? {
            switch self {
            case .noZipAsset:
                return "リリースに zip アセットがありません。"
            case .httpError(let status):
                return "ダウンロードに失敗しました（HTTP \(status)）。"
            }
        }
    }

    private let userAgent: String

    /// 更新のダウンロードは常に最新を取得したいので、URLCache を使わない専用セッションを用いる。
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    public init(userAgent: String) {
        self.userAgent = userAgent
    }

    /// リリースの `.zip` アセットを `directory` にダウンロードし、保存先 URL を返す。
    /// - Parameter fileName: 保存ファイル名（例 `"Clipkun.zip"`）。
    public func downloadZip(_ release: ReleaseInfo, into directory: URL, fileName: String) async throws -> URL {
        guard let assetURL = release.zipAssetURL else {
            throw DownloadError.noZipAsset
        }
        var request = URLRequest(url: assetURL)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (tempURL, response) = try await session.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DownloadError.httpError(status: http.statusCode)
        }

        let destination = directory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }
}

public extension ReleaseInfo {
    /// 実行中アプリのバージョン（`CFBundleShortVersionString`）。
    static var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}
