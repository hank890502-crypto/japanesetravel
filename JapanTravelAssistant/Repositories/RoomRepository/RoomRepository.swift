import Foundation

/// 用餐房間：建立、加入、成員。
protocol RoomRepository: Sendable {
    /// preferredCode：指定代碼（測試用）；nil 則由系統產生 6 碼。
    func createRoom(name: String, hostDisplayName: String, preferredCode: String?) async throws -> RoomSession
    func joinRoom(code: String, displayName: String) async throws -> RoomSession
    func members(roomId: UUID) async throws -> [RoomMember]
    /// 成員名單的即時更新。第一個值是目前名單。
    func observeMembers(roomId: UUID) async -> AsyncStream<[RoomMember]>
    func closeRoom(roomId: UUID) async throws
}

extension RoomRepository {
    func createRoom(name: String, hostDisplayName: String) async throws -> RoomSession {
        try await createRoom(name: name, hostDisplayName: hostDisplayName, preferredCode: nil)
    }
}
