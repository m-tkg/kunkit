import AppKit
import KunIntegrationProtocol

/// 自分の現在のメニューバーアイコンを kuntraykun 用の共有場所に書き出す（連携プロトコル v2）。
///
/// 他プロセス（kuntraykun）は `NSStatusItem` の画像を直接読めないため、ここで現在のアイコンを
/// PNG として共有ディレクトリに書き出し、kuntraykun が一覧に「実際のアイコン（色・状態込み）」を表示できるようにする。
/// アイコンを設定するすべての箇所（起動時・状態変化時）から呼ぶ。
/// 仕様: kuntraykun リポジトリ `docs/kun-integration-protocol.md`（v2）。
public enum KuntraykunIconExport {
    private static var baseBundleID: String {
        IntegrationProtocol.baseBundleID(Bundle.main.bundleIdentifier ?? "")
    }

    private static var dir: URL? {
        guard let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent(IntegrationProtocol.sharedIconDirRelativePath, isDirectory: true)
    }

    /// 現在のステータスアイコンを書き出す。テンプレート画像なら `<id>.template` マーカーも置く（色付きなら消す）。
    public static func export(_ image: NSImage?) {
        guard let image, let dir, !baseBundleID.isEmpty else { return }

        let side: CGFloat = 36 // 18pt @2x
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
        let pxW = max(1, Int((side * aspect).rounded()))
        let pxH = Int(side)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = NSSize(width: pxW, height: pxH)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: pxW, height: pxH))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return }

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? png.write(to: dir.appendingPathComponent("\(baseBundleID).png"), options: .atomic)
        let marker = dir.appendingPathComponent("\(baseBundleID).template")
        if image.isTemplate {
            try? Data().write(to: marker, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: marker)
        }
    }
}
