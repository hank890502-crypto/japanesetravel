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

    /// 「税込」後面的那個數字優先（380円（税込418円）→ 418）；百分比不算。
    private static let taxIncludedRegex = try! NSRegularExpression(pattern: #"税込[^0-9]{0,4}([0-9][0-9,]*(?:\.[0-9]+)?)(?!\s*[%％])"#)
    /// 第一段連續的數字（可含千分位逗號、小數）
    private static let firstNumberRegex = try! NSRegularExpression(pattern: #"[0-9][0-9,]*(?:\.[0-9]+)?"#)

    /// 使用者輸入或 ChatGPT 給的價格文字（可能含 ¥、全形數字、逗號）轉成數字。
    /// 只取「一個」數字，不把多段數字黏在一起：
    /// 540〜800 → 540、¥500/1個 → 500、380円（税込418円）→ 418、時価 → nil。
    static func parse(_ text: String) -> Decimal? {
        let normalized = PriceParser.normalize(text)
        guard !normalized.isEmpty else { return nil }
        let fullRange = NSRange(normalized.startIndex..., in: normalized)

        if let match = taxIncludedRegex.firstMatch(in: normalized, range: fullRange),
           let range = Range(match.range(at: 1), in: normalized),
           let value = decimal(from: String(normalized[range])) {
            return value
        }
        guard let match = firstNumberRegex.firstMatch(in: normalized, range: fullRange),
              let range = Range(match.range, in: normalized) else { return nil }
        return decimal(from: String(normalized[range]))
    }

    private static func decimal(from digits: String) -> Decimal? {
        let cleaned = digits.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !cleaned.isEmpty else { return nil }
        return Decimal(string: cleaned)
    }
}
