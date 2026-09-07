import Foundation
import Supabase

/// 把 Supabase / Postgres / 網路錯誤翻成白話。
/// 依「資料庫錯誤代碼」與「呼叫情境」給不同的說明：同樣是權限被擋，點餐與上傳菜單要告訴長輩不同的下一步。
enum SupabaseErrorMapper {
    /// 呼叫端在做什麼，決定 fallback 與權限錯誤的說法。
    enum Context: Sendable {
        case createRoom, joinRoom, members, closeRoom
        case saveMenu, editMenu
        case setQuantity, selections
    }

    /// Postgres 錯誤代碼（PostgrestError.code）
    enum PostgresCode {
        static let uniqueViolation = "23505"
        static let checkViolation = "23514"
        static let insufficientPrivilege = "42501"     // RLS 擋下、trigger 用 42501 拒絕
        static let raiseException = "P0001"            // 函式裡的 raise exception '...'
    }

    static func map(_ error: Error, context: Context) -> UserFacingError {
        if let userFacing = error as? UserFacingError { return userFacing }
        #if DEBUG
        print("[Supabase] \(context): \(error)")
        #endif
        if let urlError = error as? URLError {
            return UserFacingError.from(urlError) == .unknown ? .networkUnavailable : UserFacingError.from(urlError)
        }

        let postgrest = error as? PostgrestError
        let code = postgrest?.code ?? ""
        let text = [postgrest?.message, postgrest?.details, postgrest?.hint, postgrest == nil ? String(describing: error) : nil]
            .compactMap { $0 }.joined(separator: " ").lowercased()

        // 函式裡明確 raise 的狀況（訊息是我們自己定的關鍵字）
        if text.contains("room_not_found") { return .roomNotFound }
        if text.contains("not_authenticated") || text.contains("jwt") || text.contains("401") {
            return UserFacingError(title: "還沒連上", message: "請再試一次。如果一直不行，請關掉 App 重新打開。")
        }
        if text.contains("too_many_open_rooms") {
            return UserFacingError(title: "你開的房間太多了", message: "同時最多只能開 5 個房間。請先進入舊房間按「離開這個房間」，或等舊房間過期再建新的。", isRetryable: false)
        }
        if text.contains("room_rate_limited") {
            return UserFacingError(title: "建立得太頻繁了", message: "請過一個小時再建立新房間。這段時間可以繼續用現有的房間。", isRetryable: false)
        }
        if text.contains("only_host_can_edit_item") {
            return UserFacingError(title: "只有房主可以改這個", message: "家人只能幫忙改中文翻譯與備註；價格和菜名要請建立房間的人改。", isRetryable: false)
        }

        if code == PostgresCode.uniqueViolation || text.contains("duplicate key") {
            switch context {
            case .saveMenu:
                return UserFacingError(title: "這份菜單已經上傳過", message: "請回到「檢查菜單」再按一次「下一步」，App 會用新的資料重新上傳。")
            default:
                return UserFacingError(title: "資料重複了", message: "請再試一次。")
            }
        }

        if code == PostgresCode.checkViolation || text.contains("check constraint") {
            switch context {
            case .createRoom, .joinRoom, .members:
                return UserFacingError(title: "稱呼太長了", message: "請把稱呼縮短到 \(RoomMember.maxDisplayNameLength) 個字以內。", isRetryable: false)
            case .setQuantity:
                return UserFacingError(title: "數量超過上限", message: "一道菜最多點 99 份。", isRetryable: false)
            default:
                return UserFacingError(title: "資料格式不對", message: "請檢查輸入的內容再試一次。", isRetryable: false)
            }
        }

        if code == PostgresCode.insufficientPrivilege || text.contains("row-level security") || text.contains("permission denied") {
            switch context {
            case .saveMenu, .editMenu:
                return UserFacingError(title: "沒有權限", message: "只有建立房間的人可以上傳或修改菜單。請重新建立一個房間。", isRetryable: false)
            case .setQuantity, .selections:
                return UserFacingError(title: "點餐沒有送出", message: "你可能已經不在這個房間裡，或房間已經結束。請回到餐廳，用代碼重新加入。", isRetryable: false)
            case .members:
                return UserFacingError(title: "你已經不在這個房間裡", message: "請回到餐廳，用家人給的代碼重新加入。", isRetryable: false)
            case .joinRoom, .createRoom:
                return UserFacingError(title: "沒有權限", message: "請關掉 App 重新打開後再試一次。", isRetryable: false)
            case .closeRoom:
                return UserFacingError(title: "只有房主可以關閉房間", message: "你可以按「離開這個房間」，房間會留給其他人繼續用。", isRetryable: false)
            }
        }

        return fallback(for: context)
    }

    private static func fallback(for context: Context) -> UserFacingError {
        switch context {
        case .createRoom: UserFacingError(title: "無法建立房間", message: "請確認網路連線後再試一次。")
        case .joinRoom: UserFacingError(title: "無法加入房間", message: "請確認代碼與網路連線後再試一次。")
        case .saveMenu: UserFacingError(title: "菜單沒有上傳成功", message: "請確認網路連線後再試一次。")
        case .setQuantity: UserFacingError(title: "點餐沒有送出", message: "請確認網路連線後再按一次。")
        case .members, .closeRoom, .editMenu, .selections: .syncUnavailable
        }
    }
}
