import Foundation

/// 要導航去的地點。優先保存名稱、地址、座標，讓各家地圖 App 都能開。
struct Place: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var address: String?
    var latitude: Double?
    var longitude: Double?

    init(id: UUID = UUID(), name: String, address: String? = nil, latitude: Double? = nil, longitude: Double? = nil) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }

    var hasCoordinate: Bool { latitude != nil && longitude != nil }
}
