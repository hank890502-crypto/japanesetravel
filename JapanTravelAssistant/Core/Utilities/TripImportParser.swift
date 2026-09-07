import Foundation

/// 解析 ChatGPT 貼回來的行程文字。寬容：有沒有「行程開始／結束」、有沒有粗體或編號都可以。
enum TripImportParser {
    struct ImportedPlace: Hashable, Sendable {
        var name: String
        var japaneseName: String?
        var address: String?
        var category: PlaceCategory
        var note: String?
        var dayLabel: String?
        var isRecommendation: Bool = false
    }

    struct Result: Hashable, Sendable {
        var tripName: String?
        var startDate: DayDate?
        var endDate: DayDate?
        var places: [ImportedPlace]

        var itinerary: [ImportedPlace] { places.filter { !$0.isRecommendation } }
        var recommendations: [ImportedPlace] { places.filter { $0.isRecommendation } }
    }

    private static let placeMarkers: Set<String> = ["地點", "地点", "place", "スポット", "去"]
    private static let recommendationMarkers: Set<String> = ["推薦", "推荐", "recommend", "recommendation", "おすすめ"]
    private static let dayMarkers: Set<String> = ["天", "day", "第", "日"]
    private static let tripMarkers: Set<String> = ["行程", "trip", "旅程"]

    static func parse(_ text: String) -> Result {
        var lines = text.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"[*_]{1,3}"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
        // 取「最後一個」行程開始：長輩若把自己貼的提示文字（裡面有格式範本）和回覆一起複製，真正的行程在後面
        if let start = lines.lastIndex(where: { $0.contains(ChatGPTTripPrompt.startMarker) }) {
            let end = lines[(start + 1)...].firstIndex(where: { $0.contains(ChatGPTTripPrompt.endMarker) }) ?? lines.endIndex
            lines = Array(lines[(start + 1)..<end])
        }

        var result = Result(tripName: nil, startDate: nil, endDate: nil, places: [])
        var currentDay: String?

        for raw in lines {
            var line = raw
            guard !line.isEmpty, !line.hasPrefix("```") else { continue }
            line = line.replacingOccurrences(of: #"^\s*(?:[-*•・]|\d+[.、)])\s*"#, with: "", options: .regularExpression)
            line = line.trimmingCharacters(in: CharacterSet(charactersIn: "|｜ "))
            if line.range(of: #"^[-:| ｜]+$"#, options: .regularExpression) != nil { continue }
            let fields = line.replacingOccurrences(of: "｜", with: "|").components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let first = fields.first else { continue }
            let marker = first.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":： "))

            if tripMarkers.contains(marker), fields.count >= 2 {
                guard !isHeaderRow(fields[1]) else { continue }   // 範本的「行程 | 行程名稱 | 開始日期 | 結束日期」
                result.tripName = fields[1].nilIfBlank
                if fields.count > 2 { result.startDate = parseDate(fields[2]) }
                if fields.count > 3 { result.endDate = parseDate(fields[3]) }
                continue
            }
            if dayMarkers.contains(marker) || marker.hasPrefix("第") && marker.hasSuffix("天") {
                // 「天 | 第1天 | 2026-09-12 | 名古屋」→ 第1天 9/12 名古屋
                let label = fields.count >= 2 ? fields[1] : first
                let date = fields.count > 2 ? parseDate(fields[2]) : nil
                let theme = fields.count > 3 ? fields[3].nilIfBlank : nil
                currentDay = [label.nilIfBlank, date?.shortText, theme].compactMap { $0 }.joined(separator: " ")
                continue
            }
            if placeMarkers.contains(marker) || recommendationMarkers.contains(marker) {
                guard fields.count >= 2, let name = fields[1].nilIfBlank else { continue }
                // 表頭（「地點 | 中文名稱 | 日文正式名稱 | …」）不是地點
                guard !isHeaderRow(fields: Array(fields.dropFirst())) else { continue }
                let isRecommendation = recommendationMarkers.contains(marker)
                result.places.append(ImportedPlace(
                    name: name,
                    japaneseName: fields.count > 2 ? fields[2].nilIfBlank : nil,
                    address: fields.count > 3 ? fields[3].nilIfBlank : nil,
                    category: fields.count > 4 ? category(from: fields[4]) : .other,
                    note: fields.count > 5 ? fields[5].nilIfBlank : nil,
                    dayLabel: isRecommendation ? nil : currentDay,
                    isRecommendation: isRecommendation
                ))
                continue
            }
            // 沒有「地點」標記但有 ≥3 格，也當地點
            if fields.count >= 3, let name = first.nilIfBlank, !isHeaderRow(fields: fields) {
                result.places.append(ImportedPlace(
                    name: name,
                    japaneseName: fields[1].nilIfBlank,
                    address: fields[2].nilIfBlank,
                    category: fields.count > 3 ? category(from: fields[3]) : .other,
                    note: fields.count > 4 ? fields[4].nilIfBlank : nil,
                    dayLabel: currentDay
                ))
            }
        }
        return result
    }

    static func category(from text: String) -> PlaceCategory {
        let t = text.lowercased()
        if t.contains("飯店") || t.contains("旅館") || t.contains("民宿") || t.contains("hotel") || t.contains("住宿") { return .hotel }
        if t.contains("車站") || t.contains("站") || t.contains("機場") || t.contains("station") || t.contains("airport") || t.contains("交通") { return .station }
        if t.contains("餐廳") || t.contains("餐") || t.contains("食") || t.contains("restaurant") || t.contains("咖啡") || t.contains("居酒屋") { return .restaurant }
        if t.contains("商店") || t.contains("購物") || t.contains("超市") || t.contains("藥妝") || t.contains("shop") || t.contains("百貨") { return .shopping }
        if t.contains("景點") || t.contains("寺") || t.contains("神社") || t.contains("城") || t.contains("公園") || t.contains("sight") || t.contains("博物館") || t.contains("樂園") { return .sight }
        return .other
    }

    // MARK: - 表頭判斷

    /// 表格表頭或格式範本會出現的欄位名稱（ChatGPT 常自作主張加上）。
    private static let headerWords: Set<String> = [
        "中文名稱", "中文名", "名稱", "地點名稱", "行程名稱", "name", "chinesename",
        "日文名稱", "日文正式名稱", "日文名", "日文", "japanesename", "japanese",
        "地址", "日文地址", "address",
        "類型", "類別", "type", "category",
        "備註", "一句備註", "為什麼推薦", "說明", "note", "notes", "reason",
        "開始日期", "結束日期", "日期", "date",
    ]

    /// 把「日文地址（含郵遞區號）」這種寫法也當表頭：去掉括號內容、空白、標點再比對。
    static func isHeaderRow(_ text: String) -> Bool {
        var cleaned = text.lowercased()
        cleaned = cleaned.replacingOccurrences(of: #"[（(][^）)]*[）)]"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"[\s:：*_]"#, with: "", options: .regularExpression)
        return headerWords.contains(cleaned)
    }

    /// 整行看起來是表頭：第一格是表頭字，或後面至少兩格都是表頭字。
    private static func isHeaderRow(fields: [String]) -> Bool {
        guard let first = fields.first else { return false }
        if isHeaderRow(first) { return true }
        let rest = fields.dropFirst().filter { !$0.isEmpty }
        return rest.count >= 2 && rest.filter(isHeaderRow).count >= 2
    }

    // MARK: - 日期

    private static let dateFormats = ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd", "yyyy年M月d日", "M/d", "M月d日"]

    /// 日期只代表「哪一天」，解析成 DayDate，跟手機在哪個時區沒有關係。
    static func parseDate(_ text: String) -> DayDate? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        for format in dateFormats {
            formatter.dateFormat = format
            guard let date = formatter.date(from: trimmed) else { continue }
            var day = DayDate(date, calendar: calendar)
            if !format.contains("y") {
                // 只有月日：補上今年（或明年，若已經過了半年以上）
                let today = DayDate.today
                day.year = today.year
                if let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: .now), day < DayDate(sixMonthsAgo) {
                    day.year += 1
                }
            }
            return day
        }
        return nil
    }
}
