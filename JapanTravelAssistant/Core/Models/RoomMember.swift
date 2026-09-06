import Foundation

/// 房間裡的一位成員。每台裝置在同一房間只有一位成員。
struct RoomMember: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var roomId: UUID
    var userId: UUID
    var displayName: String
    var isHost: Bool
    var createdAt: Date

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
}

/// 建房或加入房間後，這台裝置在該房間的身分。
struct RoomSession: Hashable, Sendable {
    var room: DiningRoom
    var member: RoomMember
}
