import Foundation

/// 給使用者看的錯誤：一律白話中文。View 只顯示 title / message，不顯示技術細節。
struct UserFacingError: LocalizedError, Hashable, Sendable {
    var title: String
    var message: String
    var isRetryable: Bool

    init(title: String, message: String, isRetryable: Bool = true) {
        self.title = title
        self.message = message
        self.isRetryable = isRetryable
    }

    var errorDescription: String? { message }

    // MARK: - 常用預設

    static let networkUnavailable = UserFacingError(
        title: "沒有網路",
        message: "目前連不上網路，請確認手機的網路連線後再試一次。"
    )

    static let syncUnavailable = UserFacingError(
        title: "無法同步",
        message: "目前無法同步其他人的點餐內容，請確認網路連線。"
    )

    static let collaborationNotConfigured = UserFacingError(
        title: "多人點餐尚未設定",
        message: "這個版本還沒有連上多人點餐的伺服器，暫時只能自己一個人使用菜單。",
        isRetryable: false
    )

    static let aiNotEnabled = UserFacingError(
        title: "AI 分析目前尚未啟用",
        message: "你仍然可以自己輸入或修改內容。",
        isRetryable: false
    )

    static let roomNotFound = UserFacingError(
        title: "找不到這個房間",
        message: "請確認代碼有沒有打錯，或請家人再分享一次。"
    )

    /// 房間已經過期、被房主關閉、或這台手機已不是成員。
    static let roomEnded = UserFacingError(
        title: "這個房間已經結束",
        message: "房間超過兩天會自動結束，或是房主已經關閉。要再一起點餐，請重新建立房間，或請家人再分享一次代碼。",
        isRetryable: false
    )

    /// 房主的身分在這台手機上已經換掉，拿不回原本的房間。
    static let roomNeedsRecreate = UserFacingError(
        title: "這個房間需要重新建立",
        message: "這台手機的身分已經改變，沒辦法再當這個房間的房主。請回到餐廳，重新拍菜單、建立一個新房間。",
        isRetryable: false
    )

    static let cameraUnavailable = UserFacingError(
        title: "無法使用相機",
        message: "請到「設定」允許這個 App 使用相機，或改從相簿選照片。",
        isRetryable: false
    )

    static let unreadableTripFile = UserFacingError(
        title: "打不開這個旅程檔",
        message: "檔案可能在傳送時壞掉了。請請對方再分享一次，或改用 AirDrop 傳。",
        isRetryable: false
    )

    static let notRoomQRCode = UserFacingError(
        title: "這不是點餐房間的 QR Code",
        message: "請掃家人 App 裡「QR Code」按鈕顯示的那個，或直接輸入 6 碼代碼。",
        isRetryable: false
    )

    static let unknown = UserFacingError(
        title: "發生了一點問題",
        message: "請再試一次。如果還是不行，請關掉 App 重新打開。"
    )

    /// 任何 Error 轉成白話錯誤。已經是 UserFacingError 就原樣回傳。
    static func from(_ error: Error) -> UserFacingError {
        if let userFacing = error as? UserFacingError { return userFacing }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost:
                return .networkUnavailable
            default:
                break
            }
        }
        return .unknown
    }
}
