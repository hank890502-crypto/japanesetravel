import Foundation

/// 地點的類型（只影響 icon 與顏色，方便長輩辨認）。
enum PlaceCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case hotel
    case station
    case restaurant
    case shopping
    case sight
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hotel: "飯店"
        case .station: "車站"
        case .restaurant: "餐廳"
        case .shopping: "商店"
        case .sight: "景點"
        case .other: "其他"
        }
    }

    var systemImage: String {
        switch self {
        case .hotel: "bed.double.fill"
        case .station: "tram.fill"
        case .restaurant: "fork.knife"
        case .shopping: "bag.fill"
        case .sight: "camera.fill"
        case .other: "mappin.and.ellipse"
        }
    }
}

/// 要導航去的地點。優先保存名稱、地址、座標，讓各家地圖 App 都能開。
struct Place: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var address: String?
    var latitude: Double?
    var longitude: Double?
    var category: PlaceCategory
    var phone: String?
    var note: String?
    var createdAt: Date
    /// 屬於哪一趟旅程
    var tripId: UUID?
    /// 日文正式名稱（給司機看、搜地圖用）；name 是給自己看的中文
    var japaneseName: String?
    /// 行程裡的哪一天，例如「第1天 9/12」
    var dayLabel: String?
    /// 在旅程裡的順序
    var sortOrder: Int
    /// ChatGPT 推薦、但不在行程裡的景點
    var isRecommendation: Bool
    /// 為什麼推薦（來自 ChatGPT）
    var recommendationReason: String?

    init(id: UUID = UUID(), name: String, address: String? = nil, latitude: Double? = nil, longitude: Double? = nil,
         category: PlaceCategory = .other, phone: String? = nil, note: String? = nil, createdAt: Date = .now,
         tripId: UUID? = nil, japaneseName: String? = nil, dayLabel: String? = nil, sortOrder: Int = 0,
         isRecommendation: Bool = false, recommendationReason: String? = nil) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.category = category
        self.phone = phone
        self.note = note
        self.createdAt = createdAt
        self.tripId = tripId
        self.japaneseName = japaneseName
        self.dayLabel = dayLabel
        self.sortOrder = sortOrder
        self.isRecommendation = isRecommendation
        self.recommendationReason = recommendationReason
    }

    // 舊資料沒有 category 等欄位也要能讀
    private enum CodingKeys: String, CodingKey { case id, name, address, latitude, longitude, category, phone, note, createdAt, tripId, japaneseName, dayLabel, sortOrder, isRecommendation, recommendationReason }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        // 不認識的類型（例如新版 App 多加的）退回「其他」，不要讓整份資料讀不進來
        category = (try c.decodeIfPresent(String.self, forKey: .category)).flatMap(PlaceCategory.init(rawValue:)) ?? .other
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        tripId = try c.decodeIfPresent(UUID.self, forKey: .tripId)
        japaneseName = try c.decodeIfPresent(String.self, forKey: .japaneseName)
        dayLabel = try c.decodeIfPresent(String.self, forKey: .dayLabel)
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        isRecommendation = try c.decodeIfPresent(Bool.self, forKey: .isRecommendation) ?? false
        recommendationReason = try c.decodeIfPresent(String.self, forKey: .recommendationReason)
    }

    /// 給司機／店員看的名稱：有日文名用日文名
    var staffName: String { japaneseName?.nilIfBlank ?? name }

    /// 名稱正規化：去空白、統一大小寫，讓「ドーミーイン 名古屋」與「ドーミーイン名古屋」視為相同
    static func normalizedKey(_ text: String) -> String {
        text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "").lowercased()
    }

    /// 用來判斷「同一個地點」的主鍵：日文名優先
    var dedupeKey: String {
        Self.normalizedKey(japaneseName?.nilIfBlank ?? name)
    }

    /// 所有可用來合併的鍵：日文名（有的話）與中文名都算。任一相符就視為同一地點，
    /// 這樣「有日文名」與「沒日文名」的同一個地方（ChatGPT 補充匯入常只給中文名）也能合併。
    var dedupeKeys: [String] {
        var keys: [String] = []
        if let japanese = japaneseName?.nilIfBlank { keys.append(Self.normalizedKey(japanese)) }
        let nameKey = Self.normalizedKey(name)
        if !nameKey.isEmpty, !keys.contains(nameKey) { keys.append(nameKey) }
        return keys
    }

    /// 兩個名稱相同的地點是不是「明顯不同的地方」：地址都有而且不同、或座標都有而且差很遠。
    /// 舊資料遷移合併前用這個保護，避免把不同的兩家「晚餐」合成一家而把地址、電話弄丟。
    func looksLikeSamePlace(as other: Place) -> Bool {
        let a = address?.nilIfBlank.map(Self.normalizedKey), b = other.address?.nilIfBlank.map(Self.normalizedKey)
        if let a, let b, a != b { return false }
        if let lat1 = latitude, let lon1 = longitude, let lat2 = other.latitude, let lon2 = other.longitude {
            // 約 50 公尺內視為同一地點
            if abs(lat1 - lat2) > 0.0005 || abs(lon1 - lon2) > 0.0005 { return false }
        }
        return true
    }

    var hasCoordinate: Bool { latitude != nil && longitude != nil }
    var canNavigate: Bool { hasCoordinate || address?.nilIfBlank != nil }
}
