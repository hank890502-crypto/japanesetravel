import Foundation

/// 點餐：每位成員對每個品項的數量。
protocol OrderRepository: Sendable {
    /// 設定「某成員」對「某品項 + 選項組合」的數量（upsert）。quantity 0 代表取消。
    func setQuantity(roomId: UUID, memberId: UUID, menuItemId: UUID, optionIds: [UUID], quantity: Int) async throws
    func selections(roomId: UUID) async throws -> [MenuSelection]
    /// 整個房間所有人的選擇即時更新。第一個值是目前狀態。
    func observeSelections(roomId: UUID) async -> AsyncStream<[MenuSelection]>
}

extension OrderRepository {
    func setQuantity(roomId: UUID, memberId: UUID, menuItemId: UUID, quantity: Int) async throws {
        try await setQuantity(roomId: roomId, memberId: memberId, menuItemId: menuItemId, optionIds: [], quantity: quantity)
    }
}
