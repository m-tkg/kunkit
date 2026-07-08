import AppKit

/// メニューバー常駐アプリの起動時共通処理。
@MainActor
public enum KunAppLaunch {
    /// 多重起動防止: 同じ bundle ID の他インスタンスが既に動いていたら、そちらを前面に出して
    /// 自分は `exit(0)` する（常駐処理が二重に走るのを防ぐ）。
    /// `main.swift` の冒頭（`NSApplication` 生成前）で呼ぶ。
    public static func terminateIfAlreadyRunning() {
        let current = NSRunningApplication.current
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != current.processIdentifier }
        if let existing = others.first {
            existing.activate(options: [])
            exit(0)
        }
    }
}
