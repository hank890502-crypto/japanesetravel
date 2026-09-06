import Foundation

/// 一趟旅程。第一版只保留資料模型，尚無 UI。
struct Trip: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var startDate: Date?
    var endDate: Date?

    init(id: UUID = UUID(), name: String, startDate: Date? = nil, endDate: Date? = nil) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
    }
}
