import Foundation

/// 從 OCR 文字裡找出價格。純規則，不用 AI。
/// 支援：¥540、￥540、540円、540 yen、1,200、（税込594円）、全形數字、
/// 漢數字（八四〇円、千二百円）、Live Text 把 ¥ 讀成「·」的情況、各520円。
enum PriceParser {
    struct Segment: Hashable, Sendable {
        var name: String
        var price: Decimal?
    }

    /// 把一行拆成「品名」與「價格」。找不到價格時 price 為 nil、品名為整行。
    static func split(_ line: String) -> (name: String, price: Decimal?) {
        let segments = splitAll(line)
        guard let first = segments.first(where: { $0.price != nil }) else {
            return (cleanName(normalize(line)), nil)
        }
        return (first.name, first.price)
    }

    /// 一行裡可能有多組「品名 價格」（兩欄菜單被讀成同一行時）。依價格位置切段。
    static func splitAll(_ line: String) -> [Segment] {
        let normalized = normalize(line)
        let matches = allPriceMatches(in: normalized)
        guard !matches.isEmpty else {
            let name = cleanName(normalized)
            return name.isEmpty ? [] : [Segment(name: name, price: nil)]
        }

        var segments: [Segment] = []
        var cursor = normalized.startIndex
        for match in matches {
            let rawName = String(normalized[cursor..<match.range.lowerBound])
            let name = cleanName(stripPriceNoise(rawName))
            segments.append(Segment(name: name, price: match.price))
            cursor = match.range.upperBound
        }
        // 價格後面還有文字（例如「¥540 若どり唐揚げ」價格在前）→ 補給沒有品名的那段
        let tail = cleanName(stripPriceNoise(String(normalized[cursor...])))
        if !tail.isEmpty {
            if let index = segments.firstIndex(where: { $0.name.isEmpty }) {
                segments[index].name = tail
            } else {
                segments.append(Segment(name: tail, price: nil))
            }
        }
        // 品名為空但整行只有價格：品名留空，由上層決定要配給誰
        return segments
    }

    /// 整段文字本身就是一個價格（例如 OCR 把價格切成獨立的一塊）時回傳價格。
    static func priceOnly(_ text: String) -> Decimal? {
        let normalized = normalize(text)
        guard let match = allPriceMatches(in: normalized).first else { return nil }
        var rest = normalized
        rest.removeSubrange(match.range)
        rest = rest.replacingOccurrences(of: #"[（(][^）)]*[）)]"#, with: "", options: .regularExpression)
        let leftover = rest.filter { !$0.isWhitespace && !"¥円税込抜.・·:-–—…()（）各".contains($0) }
        return leftover.isEmpty ? match.price : nil
    }

    // MARK: - Private

    private struct PriceMatch {
        var range: Range<String.Index>
        var price: Decimal
    }

    private static let kanji = "[\(KanjiNumberParser.allowedCharacters)]{1,10}"

    private struct Pattern {
        let regex: NSRegularExpression
        let isKanji: Bool
    }

    private static func make(_ pattern: String, kanji: Bool = false) -> Pattern {
        Pattern(regex: try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), isKanji: kanji)
    }

    /// group 1 是數字部分。
    private static let taxIncludedPattern = make(#"[（(]?\s*税込[^0-9]{0,4}([0-9][0-9,]*)\s*円?\s*[）)]?"#)
    /// 有明確標記的價格：¥540、·540（Live Text 常把 ¥ 讀成 ·）、540円、各520円、八四〇円
    private static let markedPatterns: [Pattern] = [
        make(#"各?\s*(?:¥|[·・]\s*)([0-9][0-9,]*)(?:\s*円)?"#),
        make(#"各?\s*([0-9][0-9,]*)\s*(?:円|yen)"#),
        make("各?\\s*(\(kanji))\\s*円", kanji: true),
    ]
    /// 行尾的純數字（2–6 位），只在完全沒有標記時使用
    private static let trailingNumberPattern = make(#"(?<![0-9,.])([0-9]{2,6})\s*$"#)

    /// 優先順序：税込價 → 所有有標記的價格（可多個，依位置排序）→ 行尾純數字
    private static func allPriceMatches(in text: String) -> [PriceMatch] {
        let fullRange = NSRange(text.startIndex..., in: text)

        let taxIncluded = matches(of: taxIncludedPattern, in: text, range: fullRange)
        if !taxIncluded.isEmpty { return taxIncluded }

        var marked = markedPatterns.flatMap { matches(of: $0, in: text, range: fullRange) }
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
        // 移除重疊（同一個數字被兩個 pattern 抓到）
        var result: [PriceMatch] = []
        for match in marked where !(result.last.map { $0.range.overlaps(match.range) } ?? false) {
            result.append(match)
        }
        marked = result
        if !marked.isEmpty { return marked }

        return matches(of: trailingNumberPattern, in: text, range: fullRange)
    }

    private static func matches(of pattern: Pattern, in text: String, range: NSRange) -> [PriceMatch] {
        pattern.regex.matches(in: text, range: range).compactMap { match -> PriceMatch? in
            guard let digitsRange = Range(match.range(at: 1), in: text),
                  let wholeRange = Range(match.range, in: text) else { return nil }
            let digits = String(text[digitsRange])
            let value: Decimal?
            if pattern.isKanji {
                value = KanjiNumberParser.parse(digits).map { Decimal($0) }
            } else {
                value = Decimal(string: digits.replacingOccurrences(of: ",", with: ""))
            }
            guard let value, value > 0 else { return nil }
            return PriceMatch(range: wholeRange, price: value)
        }
    }

    /// 只把全形數字、貨幣符號、逗號、標點轉成半形；假名、漢字完全不動
    /// （不能用 fullwidthToHalfwidth transform，它會把片假名變成半形假名）。
    private static let halfwidthMap: [Character: Character] = {
        var map: [Character: Character] = ["￥": "¥", "，": ",", "、": " ", "　": " ", "．": ".", "：": ":"]
        for (index, digit) in "０１２３４５６７８９".enumerated() {
            map[digit] = Character(String(index))
        }
        return map
    }()

    static func normalize(_ text: String) -> String {
        String(text.map { halfwidthMap[$0] ?? $0 }).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 拿掉含數字的括號（税込418円）、其他帶標記的價格、空括號。「（中）」這種說明保留。
    private static func stripPriceNoise(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"[（(][^）)]*[0-9][^）)]*[）)]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?:¥\s*[0-9][0-9,]*(?:\s*円)?)|(?:[0-9][0-9,]*\s*円)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[（(]\s*[）)]"#, with: " ", options: .regularExpression)
    }

    static func cleanName(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"[.・…:：\-–—_·]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "【", with: "")
            .replacingOccurrences(of: "】", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".・…:：-–—_· 各"))
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
