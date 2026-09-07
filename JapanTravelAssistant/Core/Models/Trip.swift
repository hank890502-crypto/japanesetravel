import Foundation

/// 一趟旅程（例如「9 月名古屋」）。地點都掛在某一趟旅程底下。
/// 日期只存「哪一天」（DayDate），不含時間與時區，跨時區分享或人在日本建立都不會差一天。
struct Trip: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var startDate: DayDate?
    var endDate: DayDate?
    var createdAt: Date

    init(id: UUID = UUID(), name: String, startDate: DayDate? = nil, endDate: DayDate? = nil, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey { case id, name, startDate, endDate, createdAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        // DayDate 自己會相容舊資料（Date）；真的讀不懂就當沒填，不要讓整趟旅程讀不進來
        startDate = try? c.decodeIfPresent(DayDate.self, forKey: .startDate)
        endDate = try? c.decodeIfPresent(DayDate.self, forKey: .endDate)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
    }

    /// 例如「9/12 – 9/16」
    var dateRangeText: String? {
        switch (startDate, endDate) {
        case let (s?, e?): return s == e ? s.shortText : "\(s.shortText) – \(e.shortText)"
        case let (s?, nil): return s.shortText
        case let (nil, e?): return e.shortText
        default: return nil
        }
    }
}
