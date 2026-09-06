import Foundation

/// 解析使用者從 ChatGPT 貼回來的文字。盡量寬容：
/// - 有沒有「菜單開始／菜單結束」都可以
/// - 純文字、markdown 表格（| a | b |、|---|）、程式碼區塊、「1. 」「- 」編號都可以
/// - 也接受 JSON 陣列：[{"japanese":"…","chinese":"…","price":540,"section":"…","note":"…"}]
enum MenuImportParser {
    struct ImportedOption: Hashable, Sendable {
        var groupName: String
        var japaneseName: String
        var chineseName: String
        var priceDelta: Decimal
    }

    struct ImportedItem: Hashable, Sendable {
        var japaneseName: String
        var chineseName: String
        var price: Decimal?
        var note: String?
        var section: String?
        var sectionChinese: String? = nil
        var options: [ImportedOption] = []
        var reading: String? = nil
    }

    static let optionMarkers: Set<String> = ["選項", "选项", "option", "オプション"]
    static let sectionMarkers: Set<String> = ["分類", "分类", "類別", "类别", "section", "category", "カテゴリ", "カテゴリー"]

    static func parse(_ text: String) -> [ImportedItem] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if let json = parseJSON(trimmed), !json.isEmpty { return json }
        return parseLines(trimmed)
    }

    // MARK: - 逐行格式

    private static func parseLines(_ text: String) -> [ImportedItem] {
        var lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }

        // 只取「菜單開始」到「菜單結束」之間（如果有的話）
        if let start = lines.firstIndex(where: { $0.contains(ChatGPTMenuPrompt.startMarker) }) {
            let end = lines[(start + 1)...].firstIndex(where: { $0.contains(ChatGPTMenuPrompt.endMarker) }) ?? lines.endIndex
            lines = Array(lines[(start + 1)..<end])
        }

        var items: [ImportedItem] = []
        var currentSection: String?
        var currentSectionChinese: String?

        for rawLine in lines {
            // 粗體、斜體的星號與底線先拿掉（從 ChatGPT App 複製時常帶著）
            var line = rawLine.replacingOccurrences(of: #"[*_]{1,3}"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("```") else { continue }

            // 分類：## 日文 | 中文、分類：名稱、【名稱】
            if let section = sectionName(from: line) {
                applySection(section, currentSection: &currentSection, currentSectionChinese: &currentSectionChinese)
                continue
            }

            // 拿掉編號、項目符號、markdown 表格的外框
            line = line.replacingOccurrences(of: #"^\s*(?:[-*•・]|\d+[.、)]|[（(]\d+[）)])\s*"#, with: "", options: .regularExpression)
            line = line.trimmingCharacters(in: CharacterSet(charactersIn: "|｜ "))
            guard !line.isEmpty else { continue }

            // 表格分隔列 |---|---| 或標題列「日文 | 中文 | 價格」
            if line.range(of: #"^[-:| ｜]+$"#, options: .regularExpression) != nil { continue }

            let fields = line
                .replacingOccurrences(of: "｜", with: "|")
                .components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 2 else { continue }

            let marker = fields[0].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":： "))

            // 分類行：分類 | 日文 | 中文
            if sectionMarkers.contains(marker) {
                applySection(fields.dropFirst().joined(separator: "|"), currentSection: &currentSection, currentSectionChinese: &currentSectionChinese)
                continue
            }

            // 「## 」被 markdown 吃掉的分類行：只有兩格、沒有數字、看起來不像菜
            if fields.count == 2, !line.contains(where: \.isNumber), looksLikeSectionPair(japanese: fields[0], chinese: fields[1]) {
                applySection(line, currentSection: &currentSection, currentSectionChinese: &currentSectionChinese)
                continue
            }

            // 選項行：選項 | 群組 | 日文 | 中文 | 價差 → 掛在上一道菜
            if optionMarkers.contains(marker) {
                guard !items.isEmpty, fields.count >= 3 else { continue }
                let group = fields[1].nilIfBlank ?? "選項"
                let japanese = fields[2]
                guard !japanese.isEmpty else { continue }
                let chinese = fields.count > 3 ? fields[3] : ""
                let delta = fields.count > 4 ? (PriceFormatter.parseDelta(fields[4]) ?? 0) : 0
                items[items.count - 1].options.append(ImportedOption(groupName: group, japaneseName: japanese, chineseName: chinese, priceDelta: delta))
                continue
            }

            let japanese = fields[0]
            let chinese = fields[1]
            if isHeaderRow(japanese: japanese, chinese: chinese) { continue }
            guard !japanese.isEmpty else { continue }

            let price = fields.count > 2 ? PriceFormatter.parse(fields[2]) : nil
            let note = fields.count > 3 ? fields[3].nilIfBlank : nil
            let reading = fields.count > 4 ? fields[4].nilIfBlank : nil
            items.append(ImportedItem(japaneseName: japanese, chineseName: chinese, price: price, note: note, section: currentSection, sectionChinese: currentSectionChinese, reading: reading))
        }
        return items
    }

    private static func applySection(_ text: String, currentSection: inout String?, currentSectionChinese: inout String?) {
        let parts = text.replacingOccurrences(of: "｜", with: "|").components(separatedBy: "|").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " #")) }
        currentSection = parts.first?.nilIfBlank
        currentSectionChinese = parts.count > 1 ? parts[1].nilIfBlank : nil
    }

    /// 常見的分類名稱（整個字串要完全相等，避免「ライス｜白飯」這種菜名被誤判）。
    private static let sectionNamesJapanese: Set<String> = [
        "揚げ物", "揚物", "焼き物", "焼物", "煮物", "前菜", "冷菜", "温菜", "一品", "一品料理", "単品", "軽食", "麺類", "麺", "ご飯もの", "ご飯", "丼", "丼物", "定食", "セット",
        "刺身", "お刺身", "寿司", "鍋", "鍋物", "串焼き", "串焼", "串", "肉料理", "魚料理", "野菜料理", "サラダ", "スープ", "汁物", "デザート", "甘味", "スイーツ",
        "ドリンク", "飲み物", "飲物", "お飲み物", "アルコール", "ビール", "サワー", "ハイボール", "焼酎", "日本酒", "ワイン", "カクテル", "ソフトドリンク",
        "おつまみ", "つまみ", "おすすめ", "本日のおすすめ", "季節限定", "限定", "その他", "メイン", "主食", "朝食", "ランチ", "ディナー",
    ]
    private static let sectionNamesChinese: Set<String> = [
        "炸物", "烤物", "燒物", "煮物", "前菜", "小菜", "冷盤", "單點", "主食", "麵類", "麵", "飯類", "飯", "丼飯", "蓋飯", "套餐", "定食",
        "生魚片", "壽司", "鍋物", "火鍋", "串燒", "肉類", "魚類", "海鮮", "蔬菜", "沙拉", "湯", "湯品", "甜點", "點心", "飲料", "酒類", "啤酒", "沙瓦", "燒酎", "日本酒", "葡萄酒", "調酒", "無酒精飲料",
        "下酒菜", "推薦", "本日推薦", "季節限定", "限定", "其他", "主菜", "早餐", "午餐", "晚餐", "輕食",
    ]

    private static func looksLikeSectionPair(japanese: String, chinese: String) -> Bool {
        let ja = japanese.replacingOccurrences(of: " ", with: "")
        let zh = chinese.replacingOccurrences(of: " ", with: "")
        guard !ja.isEmpty, !zh.isEmpty else { return false }
        if sectionNamesJapanese.contains(ja) || sectionNamesChinese.contains(zh) { return true }
        if ja.hasSuffix("メニュー") || ja.hasSuffix("料理") || zh.hasSuffix("類") || zh.hasSuffix("菜單") { return true }
        return false
    }

    private static func sectionName(from line: String) -> String? {
        if line.hasPrefix("#") {
            return line.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).nilIfBlank
        }
        for prefix in ["分類：", "分類:", "類別：", "類別:"] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count)).nilIfBlank
        }
        if line.hasPrefix("【"), line.hasSuffix("】"), !line.contains("|") {
            return String(line.dropFirst().dropLast()).nilIfBlank
        }
        return nil
    }

    private static func isHeaderRow(japanese: String, chinese: String) -> Bool {
        let headerWords = ["日文", "日文原名", "原名", "japanese", "中文", "繁體中文", "chinese", "價格", "price"]
        let a = japanese.lowercased(), b = chinese.lowercased()
        return headerWords.contains(a) || headerWords.contains(b) || (a.contains("日文") && b.contains("中文"))
    }

    // MARK: - JSON

    private struct JSONItem: Decodable {
        var japanese: String?
        var japaneseName: String?
        var chinese: String?
        var chineseName: String?
        var price: FlexiblePrice?
        var note: String?
        var description: String?
        var section: String?
        var sectionChinese: String?
        var options: [JSONOption]?
        var reading: String?
        var romaji: String?
    }

    private struct JSONOption: Decodable {
        var group: String?
        var groupName: String?
        var japanese: String?
        var chinese: String?
        var priceDelta: FlexiblePrice?
        var delta: FlexiblePrice?
    }

    private enum FlexiblePrice: Decodable {
        case number(Decimal)
        case string(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Decimal.self) { self = .number(value); return }
            if let value = try? container.decode(String.self) { self = .string(value); return }
            throw DecodingError.typeMismatch(FlexiblePrice.self, .init(codingPath: decoder.codingPath, debugDescription: "price"))
        }

        var decimal: Decimal? {
            switch self {
            case .number(let value): value
            case .string(let text): PriceFormatter.parse(text)
            }
        }
    }

    private static func parseJSON(_ text: String) -> [ImportedItem]? {
        guard let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"), start < end else { return nil }
        let slice = String(text[start...end])
        guard let data = slice.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([JSONItem].self, from: data) else { return nil }
        return decoded.compactMap { item in
            guard let japanese = (item.japanese ?? item.japaneseName)?.nilIfBlank else { return nil }
            return ImportedItem(
                japaneseName: japanese,
                chineseName: (item.chinese ?? item.chineseName) ?? "",
                price: item.price?.decimal,
                note: (item.note ?? item.description)?.nilIfBlank,
                section: item.section?.nilIfBlank,
                sectionChinese: item.sectionChinese?.nilIfBlank,
                options: (item.options ?? []).compactMap { option in
                    guard let japanese = option.japanese?.nilIfBlank else { return nil }
                    return ImportedOption(
                        groupName: (option.group ?? option.groupName)?.nilIfBlank ?? "選項",
                        japaneseName: japanese,
                        chineseName: option.chinese ?? "",
                        priceDelta: (option.priceDelta ?? option.delta)?.decimal ?? 0
                    )
                },
                reading: (item.reading ?? item.romaji)?.nilIfBlank
            )
        }
    }
}
