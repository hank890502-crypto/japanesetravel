import Foundation
import Testing
@testable import JapanTravelAssistant

@Suite("菜的選項（份量、套餐、加價）")
struct MenuOptionTests {
    @Test("ChatGPT 的「選項 | 群組 | 日文 | 中文 | 價差」行會掛在上一道菜")
    func importOptions() {
        let text = """
        菜單開始
        ## 揚げ物 | 炸物
        とんかつ | 炸豬排 | 540 |
        選項 | 份量 | 大盛り | 大份 | +150
        選項 | 份量 | 小 | 小份 | -100
        選項 | 套餐 | 単品 | 單點 | 0
        選項 | 套餐 | 定食セット | 升級定食（附飯、湯、小菜） | +300
        手羽先 | 雞翅 | 430 |
        菜單結束
        """
        let items = MenuImportParser.parse(text)
        #expect(items.count == 2)
        #expect(items[0].options.count == 4)
        #expect(items[0].options.map(\.priceDelta) == [150, -100, 0, 300])
        #expect(items[0].options[3].chineseName == "升級定食（附飯、湯、小菜）")
        #expect(items[1].options.isEmpty)
    }

    @Test("價差文字解析")
    func deltaParsing() {
        #expect(PriceFormatter.parseDelta("+150") == 150)
        #expect(PriceFormatter.parseDelta("-100") == -100)
        #expect(PriceFormatter.parseDelta("−100") == -100)
        #expect(PriceFormatter.parseDelta("±0") == 0)
        #expect(PriceFormatter.parseDelta("+¥200") == 200)
        #expect(PriceFormatter.parseDelta("150円") == 150)
        #expect(PriceFormatter.parseDelta("abc") == nil)
    }

    @Test("草稿 → 正式菜單會帶出選項；舊草稿沒有 options 也能讀")
    func draftOptionsToBundle() throws {
        let draft = MenuDraft(items: [
            MenuItemDraft(japaneseName: "とんかつ", priceText: "540", options: [
                MenuOptionDraft(groupName: "份量", japaneseName: "大盛り", chineseName: "大份", priceDeltaText: "+150"),
                MenuOptionDraft(groupName: "套餐", japaneseName: "定食セット", priceDeltaText: "+300"),
                MenuOptionDraft(groupName: "", japaneseName: "無效"),
            ]),
        ])
        let bundle = draft.toBundle()
        #expect(bundle.options.count == 2)
        #expect(bundle.options(for: bundle.items[0].id).map(\.priceDelta) == [150, 300])
        // 每次上傳都是新的 ID，但選項仍正確掛在那道菜下
        let again = draft.toBundle()
        #expect(again.menu.id != bundle.menu.id)
        #expect(again.items[0].id != bundle.items[0].id)
        #expect(again.options(for: again.items[0].id).count == 2)
        #expect(draft.items[0].optionsSummary == "大份 +¥150、定食セット +¥300")

        let legacy = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","japaneseName":"手羽先","chineseName":"","priceText":"430"}"#
        let decoded = try JSONDecoder().decode(MenuItemDraft.self, from: Data(legacy.utf8))
        #expect(decoded.options.isEmpty)
    }

    @Test("彙總：同一道菜不同選項組合是不同行，單價含價差，總金額正確")
    func summaryByVariant() async throws {
        let roomId = UUID(), menuId = UUID()
        let tonkatsu = MenuItem(menuId: menuId, japaneseName: "とんかつ", price: 540, sortOrder: 0)
        let large = MenuItemOption(menuItemId: tonkatsu.id, groupName: "份量", nameJapanese: "大盛り", nameChinese: "大份", priceDelta: 150, sortOrder: 0)
        let teishoku = MenuItemOption(menuItemId: tonkatsu.id, groupName: "套餐", nameJapanese: "定食セット", nameChinese: "定食", priceDelta: 300, sortOrder: 1)
        let dad = RoomMember(roomId: roomId, userId: UUID(), displayName: "爸爸", createdAt: .now.addingTimeInterval(-20))
        let me = RoomMember(roomId: roomId, userId: UUID(), displayName: "我", isHost: true, createdAt: .now.addingTimeInterval(-10))

        let repo = InMemoryOrderRepository()
        try await repo.setQuantity(roomId: roomId, memberId: dad.id, menuItemId: tonkatsu.id, optionIds: [teishoku.id, large.id], quantity: 1)
        try await repo.setQuantity(roomId: roomId, memberId: me.id, menuItemId: tonkatsu.id, optionIds: [large.id, teishoku.id], quantity: 1) // 順序不同、同一組合
        try await repo.setQuantity(roomId: roomId, memberId: me.id, menuItemId: tonkatsu.id, quantity: 2) // 沒選項

        let selections = try await repo.selections(roomId: roomId)
        #expect(selections.count == 3)

        let lines = OrderSummaryBuilder.build(items: [tonkatsu], options: [large, teishoku], members: [dad, me], selections: selections)
        #expect(lines.count == 2)
        let plain = lines.first { $0.options.isEmpty }!
        let upgraded = lines.first { !$0.options.isEmpty }!
        #expect(plain.totalQuantity == 2)
        #expect(plain.unitPrice == 540)
        #expect(upgraded.totalQuantity == 2)
        #expect(upgraded.unitPrice == 990)
        #expect(upgraded.staffDisplayName == "とんかつ（大盛り・定食セット）")
        #expect(OrderSummaryBuilder.totalQuantity(of: lines) == 4)
        #expect(OrderSummaryBuilder.totalPrice(of: lines).map { NSDecimalNumber(decimal: $0).intValue } == 3060)
    }
}
