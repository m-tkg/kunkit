import Foundation

/// 更新チェックの共通スケジュール。全 kun アプリがこの値を参照する
/// （間隔の変更は kunkit のこの1箇所で済む）。
public enum KunUpdateSchedule {
    /// 定期サイレントチェックの間隔（6時間）。
    /// 取得は ETag 条件付き（304 はレート制限を消費しない）ためコストはほぼゼロだが、
    /// 更新検知の即時性は6時間で十分という運用判断。起動時とスリープ復帰時のチェックは別途行う。
    public static let checkInterval: TimeInterval = 6 * 60 * 60

    /// `Timer.tolerance` に渡す値（間隔の 10%。省電力のためコアレッシングを許可する）。
    public static let checkIntervalTolerance: TimeInterval = checkInterval / 10
}
