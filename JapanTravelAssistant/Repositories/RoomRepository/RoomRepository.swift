import Foundation

/// 用餐房間：建立、加入、成員。
protocol RoomRepository: Sendable {
    /// 建立房間並成為房主。代碼一律由系統產生 6 碼（沒有「指定代碼」這回事，避免任何人搶走別人的代碼）。
    func createRoom(name: String, hostDisplayName: String) async throws -> RoomSession
    func joinRoom(code: String, displayName: String) async throws -> RoomSession
    /// 回到房間前確認這台手機還是成員：房間仍開放就回傳最新的房間與成員（身分變了會自動重新加入）；
    /// 房間已結束丟 `UserFacingError.roomEnded`，房主身分已換掉丟 `UserFacingError.roomNeedsRecreate`。
    func restoreSession(_ session: RoomSession) async throws -> RoomSession
    func members(roomId: UUID) async throws -> [RoomMember]
    /// 成員名單的即時更新。第一個值是目前名單。
    func observeMembers(roomId: UUID) async -> AsyncStream<[RoomMember]>
    func closeRoom(roomId: UUID) async throws
}
