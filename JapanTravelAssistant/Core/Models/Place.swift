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

    init(id: UUID = UUID(), name: String, address: String? = nil, latitude: Double? = nil, longitude: Double? = nil,
         category: PlaceCategory = .other, phone: String? = nil, note: String? = nil, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.category = category
        self.phone = phone
        self.note = note
        self.createdAt = createdAt
    }

    // 舊資料沒有 category 等欄位也要能讀
    private enum CodingKeys: String, CodingKey { case id, name, address, latitude, longitude, category, phone, note, createdAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        category = try c.decodeIfPresent(PlaceCategory.self, forKey: .category) ?? .other
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
    }

    var hasCoordinate: Bool { latitude != nil && longitude != nil }
    var canNavigate: Bool { hasCoordinate || address?.nilIfBlank != nil }
}
