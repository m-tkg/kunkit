import ServiceManagement

/// ログイン時の自動起動を司る薄いラッパ。
/// macOS 13+ の `SMAppService.mainApp` を source of truth とし、状態はシステム側が永続化する。
@MainActor
public final class LoginItemController: ObservableObject {
    private let service = SMAppService.mainApp
    /// `.requiresApproval`（システム設定でログイン項目が無効）時に返す案内文を供給するクロージャ。
    /// アプリのローカライズを注入する（`{ L.string("login_item.requires_approval") }` など）。
    private let requiresApprovalMessage: () -> String

    @Published public private(set) var isEnabled: Bool

    public init(requiresApprovalMessage: @escaping () -> String) {
        self.requiresApprovalMessage = requiresApprovalMessage
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// システムの現在状態を再読込する（外部で変更された場合に同期する）。
    public func refresh() {
        isEnabled = service.status == .enabled
    }

    /// 自動起動の有効/無効を切り替える。失敗時・要承認時はメッセージを返す（成功時は nil）。
    @discardableResult
    public func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
        } catch {
            refresh()
            return error.localizedDescription
        }
        refresh()
        if enabled && service.status == .requiresApproval {
            return requiresApprovalMessage()
        }
        return nil
    }
}
