import Foundation

/// 顯示價格用：¥540、¥1,200。JPY 不顯示小數。
enum PriceFormatter {
    static func string(_ price: Decimal?, currency: String = "JPY") -> String? {
        guard let price else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = currency == "JPY" ? 0 : 2
        formatter.minimumFractionDigits = 0
        let number = formatter.string(from: price as NSDecimalNumber) ?? "\(price)"
        switch currency {
        case "JPY": return "¥\(number)"
        case "TWD": return "NT$\(number)"
        default: return "\(number) \(currency)"
        }
    }

    /// 價差文字：+150、-100、−100、±0、150円、+¥200 → 帶正負號的數字
    static func parseDelta(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let isNegative = trimmed.hasPrefix("-") || trimmed.hasPrefix("−") || trimmed.hasPrefix("－") || trimmed.hasPrefix("▲")
        guard let value = parse(trimmed) else {
            return trimmed.hasPrefix("±") || trimmed == "0" ? 0 : nil
        }
        return isNegative ? -value : value
    }

    /// 使用者輸入的價格文字（可能含 ¥、全形數字、逗號）轉成數字。
    static func parse(_ text: String) -> Decimal? {
        let halfwidth = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        let digits = halfwidth.filter { $0.isNumber || $0 == "." }
        guard !digits.isEmpty else { return nil }
        return Decimal(string: digits)
    }
}
