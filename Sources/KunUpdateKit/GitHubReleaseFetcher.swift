import Foundation

/// GitHub の最新リリース JSON（`/repos/<repo>/releases/latest`）を
/// **ETag 条件付きリクエスト**で取得する。
///
/// 未認証の GitHub API は IP あたり 60 リクエスト/時のレート制限があり、
/// kun シリーズ全アプリが同一 IP から毎時チェックすると容易に枯渇して 403 になる。
/// `If-None-Match` に前回の ETag を送ると、変更が無ければ 304 が返り、
/// **304 はレート制限を消費しない**ため、リリースが変わらない限りクォータをほぼ使わない。
/// ETag と前回の応答本文は `UserDefaults` にリポジトリ単位で保存する。
public struct GitHubReleaseFetcher {
    /// レート制限による 403。`resetAt` はクォータのリセット時刻（ヘッダに無ければ nil）。
    public struct RateLimitedError: LocalizedError {
        public let resetAt: Date?

        public init(resetAt: Date?) {
            self.resetAt = resetAt
        }

        public var errorDescription: String? {
            let isJapanese = Locale.preferredLanguages.first?.hasPrefix("ja") ?? false
            let resetText = resetAt.map {
                DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short)
            }
            if isJapanese {
                let suffix = resetText.map { "（\($0) 頃に解除されます）" } ?? ""
                return "GitHub API のレート制限中です\(suffix)。しばらくしてから再試行してください。"
            } else {
                let suffix = resetText.map { " (resets around \($0))" } ?? ""
                return "GitHub API rate limit exceeded\(suffix). Please retry later."
            }
        }
    }

    /// レート制限以外の HTTP エラー。
    public struct HTTPStatusError: LocalizedError {
        public let status: Int

        public var errorDescription: String? { "GitHub API HTTP \(status)" }
    }

    private let repoFullName: String
    private let userAgent: String
    private let cache: ReleaseFetchCache

    /// 更新チェックは常にサーバへ問い合わせたい（新鮮さは自前の ETag で管理する）ので、
    /// URLCache を使わない専用セッションを用いる。
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    public init(repoFullName: String, userAgent: String, defaults: UserDefaults = .standard) {
        self.repoFullName = repoFullName
        self.userAgent = userAgent
        self.cache = ReleaseFetchCache(repoFullName: repoFullName, defaults: defaults)
    }

    /// 最新リリースの JSON データを返す。
    /// 200 なら新規取得（ETag と本文をキャッシュ）、304 なら前回キャッシュの本文を返す。
    /// レート制限は `RateLimitedError`、その他の失敗は `HTTPStatusError` / URLSession のエラー。
    public func fetchLatestReleaseData() async throws -> Data {
        try await fetch(allowRetryWithoutETag: true)
    }

    private func fetch(allowRetryWithoutETag: Bool) async throws -> Data {
        guard let url = URL(string: "https://api.github.com/repos/\(repoFullName)/releases/latest") else {
            throw HTTPStatusError(status: -1)
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let cached = cache.load()
        if let cached {
            request.setValue(cached.etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HTTPStatusError(status: -1) }

        switch Self.outcome(
            status: http.statusCode,
            etag: http.value(forHTTPHeaderField: "ETag"),
            rateLimitRemaining: http.value(forHTTPHeaderField: "x-ratelimit-remaining"),
            rateLimitReset: http.value(forHTTPHeaderField: "x-ratelimit-reset"),
            data: data
        ) {
        case .fresh(let etag, let data):
            if let etag { cache.store(etag: etag, data: data) }
            return data
        case .notModified:
            if let cached { return cached.data }
            // ETag を送っていないのに 304、またはキャッシュ欠損（通常あり得ない）。
            // 壊れたキャッシュを捨てて一度だけ無条件で取り直す。
            cache.clear()
            guard allowRetryWithoutETag else { throw HTTPStatusError(status: 304) }
            return try await fetch(allowRetryWithoutETag: false)
        case .rateLimited(let resetAt):
            throw RateLimitedError(resetAt: resetAt)
        case .httpError(let status):
            throw HTTPStatusError(status: status)
        }
    }

    // MARK: - 応答判定（純粋ロジック・テスト対象）

    enum FetchOutcome: Equatable {
        case fresh(etag: String?, data: Data)
        case notModified
        case rateLimited(resetAt: Date?)
        case httpError(status: Int)
    }

    static func outcome(status: Int,
                        etag: String?,
                        rateLimitRemaining: String?,
                        rateLimitReset: String?,
                        data: Data) -> FetchOutcome {
        switch status {
        case 200:
            return .fresh(etag: etag, data: data)
        case 304:
            return .notModified
        case 403 where rateLimitRemaining == "0":
            let resetAt = rateLimitReset.flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
            return .rateLimited(resetAt: resetAt)
        default:
            return .httpError(status: status)
        }
    }
}

/// ETag と前回の応答本文の永続化（`UserDefaults`、リポジトリ単位のキー）。
struct ReleaseFetchCache {
    private let etagKey: String
    private let dataKey: String
    private let defaults: UserDefaults

    init(repoFullName: String, defaults: UserDefaults) {
        self.etagKey = "KunUpdateKit.etag.\(repoFullName)"
        self.dataKey = "KunUpdateKit.release.\(repoFullName)"
        self.defaults = defaults
    }

    func load() -> (etag: String, data: Data)? {
        guard let etag = defaults.string(forKey: etagKey),
              let data = defaults.data(forKey: dataKey) else { return nil }
        return (etag, data)
    }

    func store(etag: String, data: Data) {
        defaults.set(etag, forKey: etagKey)
        defaults.set(data, forKey: dataKey)
    }

    func clear() {
        defaults.removeObject(forKey: etagKey)
        defaults.removeObject(forKey: dataKey)
    }
}
