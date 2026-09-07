import Foundation

/// 只有「哪一天」、沒有時間也沒有時區的日期（旅程的出發／回程用）。
/// 存成 "yyyy-MM-dd" 字串，所以在日本建立、回台灣打開、或分享給不同時區的家人，都不會差一天。
/// 讀舊資料時也接受以前存的 Date（當地午夜），用手機目前的時區取年月日。
struct DayDate: Hashable, Sendable, Comparable {
    var year: Int
    var month: Int
    var day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// 取這個 Date 在指定日曆（預設手機目前時區）的年月日。
    init(_ date: Date, calendar: Calendar = .current) {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: comps.year ?? 1970, month: comps.month ?? 1, day: comps.day ?? 1)
    }

    /// 解析 "2026-09-12" 這種寫法（也接受 2026-9-2）。
    init?(string: String) {
        let parts = string.trimmingCharacters(in: .whitespaces).split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    static var today: DayDate { DayDate(.now) }

    /// "2026-09-12"
    var string: String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// 給長輩看的短寫法："9/12"
    var shortText: String { "\(month)/\(day)" }

    /// 這一天在指定日曆的 00:00（DatePicker、排序用）。
    func date(in calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    static func < (lhs: DayDate, rhs: DayDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

extension DayDate: Codable {
    /// 新格式是字串；舊格式是 Date（JSONEncoder 預設存成秒數）。兩種都能讀。
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            if let parsed = DayDate(string: text) {
                self = parsed
                return
            }
            // ISO 8601 之類含時間的字串：取日期部分
            if let prefix = text.split(separator: "T").first, let parsed = DayDate(string: String(prefix)) {
                self = parsed
                return
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "不是日期：\(text)")
        }
        if let legacy = try? container.decode(Date.self) {
            self = DayDate(legacy)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "不是日期")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }
}
