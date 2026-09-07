import Foundation

/// 行程時間表上的一站：哪一天、去哪個地點。同一個地點（飯店、車站）可以在很多天出現，
/// 但地點本身只存一份，所以「這次會去的地點」不會重複。
struct ItineraryStop: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var tripId: UUID
    var placeId: UUID
    /// 例如「第1天 9/12 名古屋」；nil = 沒標天
    var dayLabel: String?
    var sortOrder: Int

    init(id: UUID = UUID(), tripId: UUID, placeId: UUID, dayLabel: String? = nil, sortOrder: Int = 0) {
        self.id = id
        self.tripId = tripId
        self.placeId = placeId
        self.dayLabel = dayLabel
        self.sortOrder = sortOrder
    }
}
