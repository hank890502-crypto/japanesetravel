import Foundation

/// 漢數字 → 整數。日本菜單常見兩種寫法：
/// - 位置寫法：八四〇 → 840、一一五〇 → 1150
/// - 單位寫法：千二百 → 1200、五百 → 500、一万二千 → 12000
/// OCR 常把「〇」讀成英文 O 或數字 0，一併處理。
enum KanjiNumberParser {
    private static let digits: [Character: Int] = [
        "〇": 0, "零": 0, "○": 0, "O": 0, "o": 0, "0": 0, "０": 0,
        "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
        "壱": 1, "弐": 2, "参": 3,
    ]
    private static let units: [Character: Int] = ["十": 10, "百": 100, "千": 1000, "万": 10000]

    static let allowedCharacters: String = "〇零○Oo0０一二三四五六七八九壱弐参十百千万"

    static func parse(_ text: String) -> Int? {
        let chars = Array(text.filter { !$0.isWhitespace })
        guard !chars.isEmpty, chars.allSatisfy({ digits[$0] != nil || units[$0] != nil }) else { return nil }
        // 至少要有一個真正的數字字元
        guard chars.contains(where: { digits[$0] != nil }) else { return nil }

        if chars.contains(where: { units[$0] != nil }) {
            return parseWithUnits(chars)
        }
        return chars.reduce(0) { $0 * 10 + (digits[$1] ?? 0) }
    }

    private static func parseWithUnits(_ chars: [Character]) -> Int? {
        var total = 0
        var section = 0   // 萬以下的累計
        var current = 0   // 目前的數字
        for char in chars {
            if let digit = digits[char] {
                current = current * 10 + digit
            } else if let unit = units[char] {
                if unit == 10000 {
                    section += current == 0 ? 1 : current
                    total += section * unit
                    section = 0
                } else {
                    section += (current == 0 ? 1 : current) * unit
                }
                current = 0
            }
        }
        return total + section + current
    }
}
