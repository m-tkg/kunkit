import XCTest
@testable import KunUpdateKit

final class GitHubReleaseFetcherTests: XCTestCase {
    // MARK: 応答判定（純粋ロジック）

    func testOutcome200StoresETagAndData() {
        let data = Data(#"{"tag_name":"v1.0.0"}"#.utf8)
        let outcome = GitHubReleaseFetcher.outcome(
            status: 200, etag: #"W/"abc""#, rateLimitRemaining: "59", rateLimitReset: nil, data: data)
        XCTAssertEqual(outcome, .fresh(etag: #"W/"abc""#, data: data))
    }

    func testOutcome200WithoutETag() {
        let data = Data("{}".utf8)
        let outcome = GitHubReleaseFetcher.outcome(
            status: 200, etag: nil, rateLimitRemaining: nil, rateLimitReset: nil, data: data)
        XCTAssertEqual(outcome, .fresh(etag: nil, data: data))
    }

    func testOutcome304IsNotModified() {
        let outcome = GitHubReleaseFetcher.outcome(
            status: 304, etag: nil, rateLimitRemaining: "60", rateLimitReset: nil, data: Data())
        XCTAssertEqual(outcome, .notModified)
    }

    func testOutcome403WithExhaustedQuotaIsRateLimited() {
        // x-ratelimit-reset は unix 秒。
        let outcome = GitHubReleaseFetcher.outcome(
            status: 403, etag: nil, rateLimitRemaining: "0", rateLimitReset: "1783489517", data: Data())
        XCTAssertEqual(outcome, .rateLimited(resetAt: Date(timeIntervalSince1970: 1_783_489_517)))
    }

    func testOutcome403WithoutQuotaHeadersIsPlainHTTPError() {
        // レート制限以外の 403（権限等）はレート制限扱いにしない。
        let outcome = GitHubReleaseFetcher.outcome(
            status: 403, etag: nil, rateLimitRemaining: "12", rateLimitReset: nil, data: Data())
        XCTAssertEqual(outcome, .httpError(status: 403))
    }

    func testOutcomeServerErrorIsHTTPError() {
        let outcome = GitHubReleaseFetcher.outcome(
            status: 500, etag: nil, rateLimitRemaining: nil, rateLimitReset: nil, data: Data())
        XCTAssertEqual(outcome, .httpError(status: 500))
    }

    // MARK: キャッシュ（UserDefaults）

    func testCacheRoundTripAndClear() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "KunUpdateKitTests"))
        defaults.removePersistentDomain(forName: "KunUpdateKitTests")
        let cache = ReleaseFetchCache(repoFullName: "m-tkg/testkun", defaults: defaults)

        XCTAssertNil(cache.load())

        let data = Data(#"{"tag_name":"v1.2.3"}"#.utf8)
        cache.store(etag: #"W/"xyz""#, data: data)
        let loaded = try XCTUnwrap(cache.load())
        XCTAssertEqual(loaded.etag, #"W/"xyz""#)
        XCTAssertEqual(loaded.data, data)

        cache.clear()
        XCTAssertNil(cache.load())
        defaults.removePersistentDomain(forName: "KunUpdateKitTests")
    }

    func testCacheIsKeyedByRepo() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "KunUpdateKitTests2"))
        defaults.removePersistentDomain(forName: "KunUpdateKitTests2")
        let a = ReleaseFetchCache(repoFullName: "m-tkg/a", defaults: defaults)
        let b = ReleaseFetchCache(repoFullName: "m-tkg/b", defaults: defaults)
        a.store(etag: "ea", data: Data("a".utf8))
        XCTAssertNil(b.load(), "リポジトリごとに独立したキー")
        defaults.removePersistentDomain(forName: "KunUpdateKitTests2")
    }

    // MARK: レート制限エラーの文言

    func testRateLimitedErrorDescriptionMentionsReset() {
        let error = GitHubReleaseFetcher.RateLimitedError(resetAt: Date(timeIntervalSince1970: 0))
        let text = try! XCTUnwrap(error.errorDescription)
        XCTAssertTrue(text.contains("レート制限") || text.lowercased().contains("rate limit"))
    }
}
