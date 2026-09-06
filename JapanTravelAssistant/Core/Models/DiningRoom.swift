import Foundation

enum RoomStatus: String, Codable, Sendable {
    case open
    case closed
}

/// 一個「用餐房間」：一桌人一起點餐的單位。
struct DiningRoom: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var tripId: UUID?
    var name: String
    /// 6 碼、大寫、不含 0/O/1/I，例如 A8F3K2
    var roomCode: String
    /// 房主的使用者 id（Supabase 匿名使用者）。房主成員可由 members 中 isHost 取得。
    var hostUserId: UUID
    var status: RoomStatus
    var createdAt: Date
    var expiresAt: Date

    init(
        id: UUID = UUID(),
        tripId: UUID? = nil,
        name: String,
        roomCode: String,
        hostUserId: UUID,
        status: RoomStatus = .open,
        createdAt: Date = .now,
        expiresAt: Date = .now.addingTimeInterval(48 * 60 * 60)
    ) {
        self.id = id
        self.tripId = tripId
        self.name = name
        self.roomCode = roomCode
        self.hostUserId = hostUserId
        self.status = status
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    var isJoinable: Bool { status == .open && expiresAt > .now }
}
