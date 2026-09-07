import Foundation
import Supabase

struct SupabaseOrderRepository: OrderRepository {
    let service: LiveSupabaseService
    private var client: SupabaseClient { service.client }

    private struct SelectionRow: Encodable {
        var roomId: UUID; var memberId: UUID; var menuItemId: UUID
        var optionIds: [UUID]; var variantKey: String; var quantity: Int
    }

    func setQuantity(roomId: UUID, memberId: UUID, menuItemId: UUID, optionIds: [UUID], quantity: Int) async throws {
        let clamped = max(0, min(quantity, 99))
        let variantKey = MenuSelection.variantKey(for: optionIds)
        do {
            try await client.from("menu_selections")
                .upsert(
                    SelectionRow(roomId: roomId, memberId: memberId, menuItemId: menuItemId, optionIds: optionIds, variantKey: variantKey, quantity: clamped),
                    onConflict: "room_id,member_id,menu_item_id,variant_key"
                )
                .execute()
        } catch {
            throw SupabaseErrorMapper.map(error, context: .setQuantity)
        }
    }

    func selections(roomId: UUID) async throws -> [MenuSelection] {
        do {
            return try await client.from("menu_selections")
                .select()
                .eq("room_id", value: roomId.uuidString)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapper.map(error, context: .selections)
        }
    }

    func observeSelections(roomId: UUID) async -> AsyncStream<[MenuSelection]> {
        SupabaseRealtimeObserver.stream(client: client, roomId: roomId, tables: ["menu_selections"]) {
            try await selections(roomId: roomId)
        }
    }
}
