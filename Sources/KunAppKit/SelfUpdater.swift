import AppKit
import OSLog
import KunSupport
import KunUpdateKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.mtkg.kun", category: "SelfUpdater")

/// 最新リリースの zip をダウンロード・展開し、起動中の `.app` を上書きして再起動する共通実装。
///
/// 実行中のバンドルは自プロセスでは上書きできないため、旧プロセスの終了を待ってから
/// 入れ替える切り離しシェルスクリプトを起動し、自身は `NSApp.terminate` で終了する。
/// ローカルビルド（`.local`）でも本番リリースへ更新できるよう、bundle ID は基底 ID で比較する
/// （`BundleIdentity`）。
@MainActor
public final class SelfUpdater {
    /// 自己更新の失敗。文言は ja/en に対応する（更新失敗はまれかつエッジケース）。
    public enum SelfUpdateError: LocalizedError {
        case notWritable(String)
        case archiveNotFound
        case commandFailed(String)
        case bundleNotFound
        case bundleIDMismatch

        public var errorDescription: String? {
            let ja = Locale.preferredLanguages.first?.hasPrefix("ja") ?? false
            switch self {
            case .notWritable(let path):
                return ja ? "書き込み権限がありません: \(path)" : "No write permission: \(path)"
            case .archiveNotFound:
                return ja ? "ダウンロードした zip が見つかりません。" : "Downloaded archive not found."
            case .commandFailed(let msg):
                return ja ? "コマンドが失敗しました: \(msg)" : "Command failed: \(msg)"
            case .bundleNotFound:
                return ja ? "アーカイブ内に .app が見つかりません。" : "No .app found in the archive."
            case .bundleIDMismatch:
                return ja ? "アーカイブの bundle ID が一致しません。" : "Archive bundle ID does not match."
            }
        }
    }

    /// 一時ディレクトリ名・保存 zip 名に使うアプリ名（例 `"Clipkun"`）。
    private let appName: String
    private let downloader: ReleaseDownloader

    /// - Parameters:
    ///   - appName: 一時ディレクトリ・zip ファイル名に使う（例 `"Clipkun"`）。
    ///   - userAgent: ダウンロード時の User-Agent（既定は appName）。
    public init(appName: String, userAgent: String? = nil) {
        self.appName = appName
        self.downloader = ReleaseDownloader(userAgent: userAgent ?? appName)
    }

    /// 更新を実行する。成功した場合はアプリを終了するため、呼び出し元には戻らない。
    public func performUpdate(to release: ReleaseInfo) async throws {
        let bundleURL = Bundle.main.bundleURL
        try ensureWritable(bundleURL)

        let fm = FileManager.default
        let workDir = fm.temporaryDirectory
            .appendingPathComponent("\(appName)-update-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)

        let zipURL = try await downloader.downloadZip(release, into: workDir, fileName: "\(appName).zip")

        let extractDir = workDir.appendingPathComponent("extracted", isDirectory: true)
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try await runAndWait("/usr/bin/ditto", ["-x", "-k", zipURL.path, extractDir.path])

        guard let newApp = try firstFile(in: extractDir, pathExtension: "app") else {
            throw SelfUpdateError.bundleNotFound
        }
        // ローカルビルド（`.local` サフィックス）でも本番リリースへ更新できるよう、基底 ID で比較する。
        guard let newBundleID = Bundle(url: newApp)?.bundleIdentifier,
              BundleIdentity.baseID(newBundleID) == BundleIdentity.baseID(Bundle.main.bundleIdentifier) else {
            throw SelfUpdateError.bundleIDMismatch
        }

        try launchReplaceScript(newApp: newApp, dest: bundleURL)
        logger.info("Relaunch script started; terminating for update to \(release.tagName, privacy: .public)")
        NSApp.terminate(nil)
    }

    private func ensureWritable(_ bundleURL: URL) throws {
        let fm = FileManager.default
        let parent = bundleURL.deletingLastPathComponent().path
        guard fm.isWritableFile(atPath: parent), fm.isWritableFile(atPath: bundleURL.path) else {
            throw SelfUpdateError.notWritable(bundleURL.path)
        }
    }

    private func firstFile(in directory: URL, pathExtension: String) throws -> URL? {
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
        return entries.first { $0.pathExtension == pathExtension }
    }

    /// 旧プロセス終了を待って `.app` を入れ替え、再起動する切り離しスクリプトを起動する。
    private func launchReplaceScript(newApp: URL, dest: URL) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf "$DEST.bak"
        mv "$DEST" "$DEST.bak" || exit 1
        if ! mv "$NEW" "$DEST"; then
          mv "$DEST.bak" "$DEST"
          exit 1
        fi
        rm -rf "$DEST.bak"
        xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
        open "$DEST"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.environment = [
            "DEST": dest.path,
            "NEW": newApp.path,
            "PATH": "/usr/bin:/bin",
        ]
        try process.run()
    }

    private func runAndWait(_ executable: String, _ arguments: [String]) async throws {
        do {
            _ = try await ProcessRunner.run(executable: executable, arguments: arguments)
        } catch let failure as ProcessRunner.Failure {
            logger.error("Command failed (\(executable, privacy: .public) exit=\(failure.exitCode)): \(failure.conciseMessage, privacy: .public)")
            throw SelfUpdateError.commandFailed(failure.conciseMessage)
        }
    }
}
