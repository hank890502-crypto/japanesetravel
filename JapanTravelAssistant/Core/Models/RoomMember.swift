import Foundation

/// 房間裡的一位成員。每台裝置在同一房間只有一位成員。
struct RoomMember: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var roomId: UUID
    var userId: UUID
    var displayName: String
    var isHost: Bool
    var createdAt: Date

    /// 稱呼最多 30 個字（資料庫 room_members.display_name 的限制）。輸入時就截斷並提示，不讓長輩撞到伺服器錯誤。
    static let maxDisplayNameLength = 30

    init(
        id: UUID = UUID(),
        roomId: UUID,
        userId: UUID,
        displayName: String,
        isHost: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.roomId = roomId
        self.userId = userId
        self.displayName = displayName
        self.isHost = isHost
        self.createdAt = createdAt
    }

    /// 把稱呼截到上限（以「字」計，不是 byte）。
    static func clampDisplayName(_ name: String) -> String {
        String(name.prefix(maxDisplayNameLength))
    }
}

/// 建房或加入房間後，這台裝置在該房間的身分。
struct RoomSession: Hashable, Sendable {
    var room: DiningRoom
    var member: RoomMember
}
