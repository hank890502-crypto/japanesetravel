import Foundation

/// 房間代碼：6 碼大寫，去掉 0 / O / 1 / I 避免看錯。
/// 正式環境由資料庫端 create_room() 產生；這裡給本機 / 測試 / 驗證用。
enum RoomCodeGenerator {
    static let alphabet: [Character] = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static let length = 6

    static func generate() -> String {
        String((0..<length).map { _ in alphabet.randomElement()! })
    }

    /// 使用者輸入的清理：全形英數折成半形（LINE 或注音鍵盤常打出「Ａ８Ｆ３Ｋ２」）、去空白與連字號、轉大寫。
    static func normalize(_ input: String) -> String {
        let halfwidth = input.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? input
        return String(halfwidth.uppercased().filter { !$0.isWhitespace && $0 != "-" })
    }

    /// 正式代碼是 6 碼；為了容忍舊連結與手打，接受 4～8 碼的半形英數字。
    static func isValid(_ code: String) -> Bool {
        (4...8).contains(code.count) && code.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}
