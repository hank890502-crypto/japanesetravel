import CoreGraphics
import Foundation

/// 版面分析後的一筆候選：可能是一道菜（有價格），也可能是其他文字。
struct MenuCandidate: Hashable, Sendable {
    var name: String
    var price: Decimal?
    var confidence: Double
    var sourceText: String
    /// Vision 座標；Live Text 沒有座標時為 .zero
    var box: CGRect = .zero
    /// 所屬分類（辨識到「揚げ物」這類標題時套用到後面的菜）
    var section: String? = nil
}

struct MenuParseResult: Hashable, Sendable {
    var items: [MenuCandidate]
    var otherLines: [MenuCandidate]

    static let empty = MenuParseResult(items: [], otherLines: [])
}
