import Foundation
import Testing
@testable import JapanTravelAssistant

/// 選項組合鍵（variant_key）三邊一致：App、網頁版（web/guest/app.js 的 variantKey）、資料庫 trigger。
/// 規則：小寫 UUID、排序後用「,」連接；沒有選項是空字串。
@Suite("選項組合鍵")
struct VariantKeyTests {
    @Test("小寫、排序、逗號；順序不同也是同一組合")
    func format() {
        let a = UUID(uuidString: "1C4E0F5A-7B6D-4C8E-9A2B-3D4E5F6A7B8C")!
        let b = UUID(uuidString: "9AB2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D")!
        let key = MenuSelection.variantKey(for: [b, a])
        #expect(key == "1c4e0f5a-7b6d-4c8e-9a2b-3d4e5f6a7b8c,9ab2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d")
        #expect(key == MenuSelection.variantKey(for: [a, b]))
        #expect(key == key.lowercased())
        #expect(!key.contains("+"))
        #expect(MenuSelection.variantKey(for: []) == "")
    }

    @Test("MenuSelection、[MenuItemOption]、InMemoryOrderRepository 用的都是同一條規則")
    func consistentAcrossTypes() async throws {
        let item = UUID()
        let large = MenuItemOption(menuItemId: item, groupName: "份量", nameJapanese: "大盛り", priceDelta: 150, sortOrder: 0)
        let set = MenuItemOption(menuItemId: item, groupName: "套餐", nameJapanese: "定食", priceDelta: 300, sortOrder: 1)
        let selection = MenuSelection(roomId: UUID(), memberId: UUID(), menuItemId: item, optionIds: [set.id, large.id], quantity: 1)
        #expect(selection.variantKey == [large, set].variantKey)
        #expect(selection.variantKey == MenuSelection.variantKey(for: [large.id, set.id]))

        // 網頁版用同一組 id 算出來的字串（[...ids].map(lower).sort().join(",")）要等於 App 的
        let webStyle = [set.id, large.id].map { $0.uuidString.lowercased() }.sorted().joined(separator: ",")
        #expect(webStyle == selection.variantKey)

        let repo = InMemoryOrderRepository()
        let roomId = UUID(), member = UUID()
        try await repo.setQuantity(roomId: roomId, memberId: member, menuItemId: item, optionIds: [set.id, large.id], quantity: 1)
        try await repo.setQuantity(roomId: roomId, memberId: member, menuItemId: item, optionIds: [large.id, set.id], quantity: 2)
        let rows = try await repo.selections(roomId: roomId)
        #expect(rows.count == 1 && rows.first?.quantity == 2)
    }
}
