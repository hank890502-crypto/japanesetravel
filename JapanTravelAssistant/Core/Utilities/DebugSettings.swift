import Foundation

/// 測試用開關。正式版一律忽略。
enum DebugSettings {
    /// 建立房間時指定固定代碼（例如 "0000"），方便兩台手機反覆測試。
    /// nil = 由系統產生隨機 6 碼（目前設定）。
    static var fixedRoomCode: String? { nil }
}
