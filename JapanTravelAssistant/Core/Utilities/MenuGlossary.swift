import Foundation

/// 內建的菜單詞彙表（日→繁中）。不需要網路與 AI，立刻能給出「看得懂」的中文。
/// 做法：從左到右做最長字串比對，把認得的詞換成中文；認得的比例太低就放棄（交給系統翻譯）。
final class MenuGlossary: Sendable {
    private let entries: [String: String]
    private let keysByLength: [String]

    init(entries: [String: String]) {
        self.entries = entries
        self.keysByLength = entries.keys.sorted { $0.count > $1.count }
    }

    static let bundled: MenuGlossary = {
        guard let url = Bundle.main.url(forResource: "menu-glossary", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            assertionFailure("menu-glossary.json 載入失敗")
            return MenuGlossary(entries: [:])
        }
        return MenuGlossary(entries: decoded)
    }()

    /// 回傳中文；認得的字不到一半就回傳 nil。
    func translate(_ japanese: String, minimumCoverage: Double = 0.5) -> String? {
        let text = japanese.replacingOccurrences(of: " ", with: "")
        guard !text.isEmpty else { return nil }
        if let exact = entries[text] { return exact }

        var output = ""
        var matchedCount = 0
        var index = text.startIndex
        while index < text.endIndex {
            let rest = text[index...]
            if let key = keysByLength.first(where: { rest.hasPrefix($0) }) {
                output += entries[key] ?? key
                matchedCount += key.count
                index = text.index(index, offsetBy: key.count)
            } else {
                let char = text[index]
                // 沒認得的字：括號、符號、漢字照抄（中文使用者看得懂），假名也照抄
                output.append(char)
                if char.isPunctuation || char.isSymbol || char.isNumber { matchedCount += 1 }
                index = text.index(after: index)
            }
        }
        let coverage = Double(matchedCount) / Double(text.count)
        return coverage >= minimumCoverage ? output : nil
    }
}
