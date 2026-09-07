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
    }

    struct Result: Hashable, Sendable {
        var tripName: String?
        var startDate: Date?
        var endDate: Date?
        var places: [ImportedPlace]
    }

    private static let placeMarkers: Set<String> = ["地點", "地点", "place", "スポット"]
    private static let dayMarkers: Set<String> = ["天", "day", "第", "日"]
    private static let tripMarkers: Set<String> = ["行程", "trip", "旅程"]

    static func parse(_ text: String) -> Result {
        var lines = text.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"[*_]{1,3}"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
        if let start = lines.firstIndex(where: { $0.contains(ChatGPTTripPrompt.startMarker) }) {
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
                currentDay = [label.nilIfBlank, date.map(shortDate), theme].compactMap { $0 }.joined(separator: " ")
                continue
            }
            if placeMarkers.contains(marker) {
                guard fields.count >= 2, let name = fields[1].nilIfBlank else { continue }
                result.places.append(ImportedPlace(
                    name: name,
                    japaneseName: fields.count > 2 ? fields[2].nilIfBlank : nil,
                    address: fields.count > 3 ? fields[3].nilIfBlank : nil,
                    category: fields.count > 4 ? category(from: fields[4]) : .other,
                    note: fields.count > 5 ? fields[5].nilIfBlank : nil,
                    dayLabel: currentDay
                ))
                continue
            }
            // 沒有「地點」標記但有 ≥3 格，也當地點
            if fields.count >= 3, let name = first.nilIfBlank, !isHeaderRow(first) {
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

    private static func isHeaderRow(_ text: String) -> Bool {
        ["中文名稱", "名稱", "name", "地點名稱"].contains(text.lowercased())
    }

    private static let dateFormats = ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd", "M/d", "M月d日", "yyyy年M月d日"]

    static func parseDate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current   // 日期只是「哪一天」，用手機的時區解析與顯示才一致
        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                // 只有月日：補上今年（或明年，若已經過了）
                if !format.contains("y") {
                    var comps = Calendar.current.dateComponents([.month, .day], from: date)
                    comps.year = Calendar.current.component(.year, from: .now)
                    if let d = Calendar.current.date(from: comps) {
                        return d < Calendar.current.date(byAdding: .month, value: -6, to: .now)! ? Calendar.current.date(byAdding: .year, value: 1, to: d) : d
                    }
                }
                return date
            }
        }
        return nil
    }

    static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d"
        return f.string(from: date)
    }
}
