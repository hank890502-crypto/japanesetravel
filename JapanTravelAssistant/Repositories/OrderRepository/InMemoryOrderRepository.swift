import Foundation

actor InMemoryOrderRepository: OrderRepository {
    private struct Key: Hashable {
        let roomId: UUID
        let memberId: UUID
        let menuItemId: UUID
        let variantKey: String
    }

    private var selections: [Key: MenuSelection] = [:]
    private var observers = ObserverRegistry<[MenuSelection]>()

    init() {}

    func setQuantity(roomId: UUID, memberId: UUID, menuItemId: UUID, optionIds: [UUID], quantity: Int) async throws {
        let clamped = max(0, min(quantity, 99))
        let variantKey = optionIds.map(\.uuidString).sorted().joined(separator: "+")
        let key = Key(roomId: roomId, memberId: memberId, menuItemId: menuItemId, variantKey: variantKey)
        if var existing = selections[key] {
            existing.quantity = clamped
            existing.updatedAt = .now
            selections[key] = existing
        } else {
            selections[key] = MenuSelection(roomId: roomId, memberId: memberId, menuItemId: menuItemId, optionIds: optionIds, quantity: clamped)
        }
        broadcast(roomId: roomId)
    }

    func selections(roomId: UUID) async throws -> [MenuSelection] {
        list(roomId: roomId)
    }

    func observeSelections(roomId: UUID) async -> AsyncStream<[MenuSelection]> {
        let stream = observers.makeStream(key: roomId) { [weak self] id in
            Task { await self?.removeObserver(id) }
        }
        observers.broadcast(key: roomId, value: list(roomId: roomId))
        return stream
    }

    // MARK: - Private

    private func list(roomId: UUID) -> [MenuSelection] {
        selections.values.filter { $0.roomId == roomId }.sorted { $0.updatedAt < $1.updatedAt }
    }

    private func broadcast(roomId: UUID) {
        observers.broadcast(key: roomId, value: list(roomId: roomId))
    }

    private func removeObserver(_ id: UUID) {
        observers.remove(id: id)
    }
}
