import Foundation

/// 一趟旅程（例如「9 月名古屋」）。地點都掛在某一趟旅程底下。
struct Trip: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var startDate: Date?
    var endDate: Date?
    var createdAt: Date

    init(id: UUID = UUID(), name: String, startDate: Date? = nil, endDate: Date? = nil, createdAt: Date = .now) {
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
        startDate = try c.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(Date.self, forKey: .endDate)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
    }

    /// 例如「9/12 – 9/16」
    var dateRangeText: String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        formatter.dateFormat = "M/d"
        switch (startDate, endDate) {
        case let (s?, e?): return s == e ? formatter.string(from: s) : "\(formatter.string(from: s)) – \(formatter.string(from: e))"
        case let (s?, nil): return formatter.string(from: s)
        case let (nil, e?): return formatter.string(from: e)
        default: return nil
        }
    }
}
