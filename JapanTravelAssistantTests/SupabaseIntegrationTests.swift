import Foundation
import Testing
@testable import JapanTravelAssistant

/// 對真實 Supabase 專案的整合測試。只有 App 有設定 SUPABASE_URL 時才會跑，否則整個 suite 跳過。
/// 會在資料庫留下一個代碼 TEST01 的房間（下次跑會自動關掉舊的）。
@Suite("Supabase 整合（需要真實專案）")
struct SupabaseIntegrationTests {
    private static var config: AppConfig { AppConfig.fromBundle(Bundle(for: TestHost.self)) }
    private final class TestHost {}

    @Test("建房 → 上傳菜單 → 點餐 → 讀回 → 即時串流第一筆")
    func endToEnd() async throws {
        let config = AppConfig.fromBundle(Bundle.main)
        guard let url = config.supabaseURL, let key = config.supabaseAnonKey else {
            print("沒有 Supabase 設定，跳過整合測試")
            return
        }
        let service = LiveSupabaseService(url: url, anonKey: key)
        let rooms = SupabaseRoomRepository(service: service)
        let menus = SupabaseMenuRepository(service: service)
        let orders = SupabaseOrderRepository(service: service)

        let session = try await rooms.createRoom(name: "整合測試", hostDisplayName: "測試主", preferredCode: "TEST01")
        #expect(session.room.roomCode == "TEST01")
        #expect(session.member.isHost)

        let draft = MenuDraft(restaurantName: "測試店", items: [
            MenuItemDraft(japaneseName: "若どり唐揚げ", chineseName: "炸嫩雞", priceText: "540", sectionName: "揚げ物", reading: "wakadori karaage"),
            MenuItemDraft(japaneseName: "とんかつ", priceText: "540", sectionName: "揚げ物", options: [
                MenuOptionDraft(groupName: "份量", japaneseName: "大盛り", chineseName: "大份", priceDeltaText: "+150"),
            ]),
        ], sectionChineseNames: ["揚げ物": "炸物"])
        let saved = try await menus.saveMenu(draft.toBundle(), toRoom: session.room.id)

        // 同一份草稿再建一個房間、再上傳一次，不能撞 ID
        let second = try await rooms.createRoom(name: "整合測試 2", hostDisplayName: "測試主", preferredCode: "TEST02")
        _ = try await menus.saveMenu(draft.toBundle(), toRoom: second.room.id)
        try await rooms.closeRoom(roomId: second.room.id)

        let fetched = try await menus.menus(roomId: session.room.id)
        #expect(fetched.count == 1)
        #expect(fetched.first?.items.count == 2)
        #expect(fetched.first?.sections.first?.nameChinese == "炸物")
        #expect(fetched.first?.options.first?.priceDelta == 150)
        #expect(fetched.first?.items.first { $0.japaneseName == "若どり唐揚げ" }?.reading == "wakadori karaage")

        let joined = try await rooms.joinRoom(code: "test01", displayName: "測試主改名")
        #expect(joined.member.id == session.member.id)
        let members = try await rooms.members(roomId: session.room.id)
        #expect(members.count == 1 && members.first?.displayName == "測試主改名")

        let tonkatsu = saved.items.first { $0.japaneseName == "とんかつ" }!
        let large = saved.options.first!
        try await orders.setQuantity(roomId: session.room.id, memberId: session.member.id, menuItemId: tonkatsu.id, optionIds: [large.id], quantity: 2)
        try await orders.setQuantity(roomId: session.room.id, memberId: session.member.id, menuItemId: tonkatsu.id, optionIds: [large.id], quantity: 3) // upsert
        let selections = try await orders.selections(roomId: session.room.id)
        #expect(selections.count == 1)
        #expect(selections.first?.quantity == 3)
        #expect(selections.first?.optionIds == [large.id])

        // 即時串流：至少要拿到第一筆（目前狀態）
        let stream = await orders.observeSelections(roomId: session.room.id)
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first?.first?.quantity == 3)

        // 找不到的代碼
        await #expect(throws: UserFacingError.self) {
            _ = try await rooms.joinRoom(code: "ZZZZZZ", displayName: "x")
        }

        try await rooms.closeRoom(roomId: session.room.id)
    }
}
