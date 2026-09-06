import Foundation

extension String {
    /// 去頭尾空白後若為空字串則回傳 nil。
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
