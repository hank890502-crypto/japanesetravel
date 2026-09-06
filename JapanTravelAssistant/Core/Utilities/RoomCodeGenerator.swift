import Foundation

/// 房間代碼：6 碼大寫，去掉 0 / O / 1 / I 避免看錯。
/// 正式環境由資料庫端 create_room() 產生；這裡給本機 / 測試 / 驗證用。
enum RoomCodeGenerator {
    static let alphabet: [Character] = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static let length = 6

    static func generate() -> String {
        String((0..<length).map { _ in alphabet.randomElement()! })
    }

    /// 使用者輸入的清理：去空白與連字號、轉大寫。
    static func normalize(_ input: String) -> String {
        String(input.uppercased().filter { !$0.isWhitespace && $0 != "-" })
    }

    /// 正式代碼是 6 碼；測試用的固定代碼（例如 0000）也接受：4～8 碼英數字。
    static func isValid(_ code: String) -> Bool {
        (4...8).contains(code.count) && code.allSatisfy { $0.isLetter || $0.isNumber }
    }
}
