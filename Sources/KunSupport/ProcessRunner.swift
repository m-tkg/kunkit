import Foundation
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.mtkg.kun", category: "ProcessRunner")

/// 外部コマンドを起動して stdout を返す共通ランナー。
///
/// stdout/stderr は `readabilityHandler` で逐次読み出して蓄積する。
/// `terminationHandler` 内で `readDataToEndOfFile` を呼ぶ実装だと、出力が pipe バッファ
/// （macOS では概ね 64KB）を超えた瞬間に process が write でブロックして exit せず、
/// terminationHandler が呼ばれない deadlock になるため、こちらの形を採る。
public enum ProcessRunner {

    /// exit code が 0 以外だったときに投げる。エラーの意味付けは呼び出し側で行う。
    public struct Failure: Error {
        public let exitCode: Int32
        public let stderr: String

        public init(exitCode: Int32, stderr: String) {
            self.exitCode = exitCode
            self.stderr = stderr
        }
    }

    /// プロセスを起動し、正常終了（exit 0）なら stdout を返す。
    /// `environment` が nil の場合は親プロセスの環境を継承する。
    public static func run(executable: String,
                           arguments: [String],
                           environment: [String: String]? = nil) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let box = OutputBox()

        return try await withCheckedThrowingContinuation { continuation in
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    box.appendOut(chunk)
                }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    box.appendErr(chunk)
                }
            }

            process.terminationHandler = { proc in
                // ハンドラを外して残りのデータを読み切る。
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                if let remaining = try? outPipe.fileHandleForReading.readToEnd() {
                    box.appendOut(remaining)
                }
                if let remaining = try? errPipe.fileHandleForReading.readToEnd() {
                    box.appendErr(remaining)
                }

                let (stdout, stderr) = box.snapshot()
                let errMsg = String(data: stderr, encoding: .utf8) ?? ""
                let outPreview = String(data: stdout.prefix(200), encoding: .utf8) ?? ""
                logger.info("exit=\(proc.terminationStatus) stderr=\"\(errMsg)\" stdout_preview=\"\(outPreview)\"")

                box.resumeOnce {
                    guard proc.terminationStatus == 0 else {
                        continuation.resume(throwing: Failure(exitCode: proc.terminationStatus,
                                                              stderr: errMsg))
                        return
                    }
                    continuation.resume(returning: stdout)
                }
            }

            do {
                try process.run()
            } catch {
                box.resumeOnce { continuation.resume(throwing: error) }
            }
        }
    }
}

/// stdout/stderr の蓄積と一度きりの継続再開をスレッドセーフに行う内部アキュムレータ。
/// 参照型にすることで、複数のハンドラ／終了コールバックから安全に更新できる
/// （キャプチャ変数の並行変更を避ける）。
private final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var outData = Data()
    private var errData = Data()
    private var hasResumed = false

    func appendOut(_ data: Data) {
        lock.lock(); outData.append(data); lock.unlock()
    }

    func appendErr(_ data: Data) {
        lock.lock(); errData.append(data); lock.unlock()
    }

    func snapshot() -> (out: Data, err: Data) {
        lock.lock(); defer { lock.unlock() }
        return (outData, errData)
    }

    func resumeOnce(_ action: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return }
        hasResumed = true
        action()
    }
}

extension ProcessRunner.Failure {
    /// stderr を1行のエラーメッセージ用文字列に整形する。空なら exit code にフォールバックする。
    public var conciseMessage: String {
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "exit \(exitCode)" : trimmed
    }
}
