import Foundation
import Testing
@testable import JapanTravelAssistant

@Suite("ChatGPT 匯入")
struct MenuImportTests {
    @Test("標準格式：標記、分類、四欄")
    func standardFormat() {
        let text = """
        好的，以下是翻譯：
        菜單開始
        ## 揚げ物
        若どり唐揚げ | 日式炸嫩雞 | 540 | 外酥內嫩的雞腿肉
        手羽先 | 雞翅 | 430 |
        ## 焼き物
        ねぎま | 蔥段雞肉串 | 180 | 雞肉夾蔥
        菜單結束
        希望對你有幫助！
        """
        let items = MenuImportParser.parse(text)
        #expect(items.map(\.japaneseName) == ["若どり唐揚げ", "手羽先", "ねぎま"])
        #expect(items.map(\.chineseName) == ["日式炸嫩雞", "雞翅", "蔥段雞肉串"])
        #expect(items.map(\.price) == [540, 430, 180])
        #expect(items.map(\.section) == ["揚げ物", "揚げ物", "焼き物"])
        #expect(items[0].note == "外酥內嫩的雞腿肉")
        #expect(items[1].note == nil)
    }

    @Test("ChatGPT 硬要用 markdown 表格、編號、程式碼區塊也能解析")
    func markdownVariants() {
        let text = """
        ```
        | 日文原名 | 繁體中文 | 價格 | 說明 |
        |---|---|---|---|
        | 味噌串カツ | 味噌炸串 | ¥540 | 名古屋名物 |
        | 生ビール（中） | 生啤酒（中杯） | 650円 | |
        ```
        1. 枝豆｜毛豆｜380
        - ライス | 白飯 |
        """
        let items = MenuImportParser.parse(text)
        #expect(items.map(\.japaneseName) == ["味噌串カツ", "生ビール（中）", "枝豆", "ライス"])
        #expect(items.map(\.price) == [540, 650, 380, nil])
        #expect(items[0].note == "名古屋名物")
    }

    @Test("JSON 也可以")
    func jsonFormat() {
        let text = """
        [{"japanese":"若どり唐揚げ","chinese":"炸嫩雞","price":540,"section":"揚げ物"},
         {"japanese":"手羽先","chinese":"雞翅","price":"¥430","note":"名古屋風"}]
        """
        let items = MenuImportParser.parse(text)
        #expect(items.count == 2)
        #expect(items[0].section == "揚げ物")
        #expect(items[1].price == 430)
        #expect(items[1].note == "名古屋風")
    }

    @Test("匯入會跟現有菜單合併：對得上的更新，對不上的新增")
    @MainActor
    func mergeIntoExistingDraft() {
        let store = MenuDraftStore(directory: nil)
        store.draft = MenuDraft(items: [
            MenuItemDraft(japaneseName: "若どり唐揚げ", priceText: "540"),
            MenuItemDraft(japaneseName: "手先", priceText: "430"),   // OCR 漏字
        ], otherLines: [MenuItemDraft(japaneseName: "ねぎま")])

        let summary = store.merge(imported: [
            .init(japaneseName: "若どり唐揚げ", chineseName: "日式炸嫩雞", price: 540, note: nil, section: "揚げ物"),
            .init(japaneseName: "ねぎま", chineseName: "蔥段雞肉串", price: 180, note: nil, section: "焼き物"),
        ])
        #expect(summary.updated == 1)
        #expect(summary.added == 1)
        let items = store.draft!.items
        #expect(items.count == 3)
        #expect(items[0].chineseName == "日式炸嫩雞")
        #expect(items[0].sectionName == "揚げ物")
        #expect(items[2].japaneseName == "ねぎま")
        #expect(store.draft!.otherLines.isEmpty)
    }

    @Test("草稿轉正式菜單時會建立分類")
    func sectionsInBundle() {
        let draft = MenuDraft(items: [
            MenuItemDraft(japaneseName: "若どり唐揚げ", chineseName: "炸雞", priceText: "540", sectionName: "揚げ物"),
            MenuItemDraft(japaneseName: "ねぎま", priceText: "180", sectionName: "焼き物", note: "雞肉夾蔥"),
            MenuItemDraft(japaneseName: "手羽先", priceText: "430", sectionName: "揚げ物"),
        ])
        let bundle = draft.toBundle()
        #expect(bundle.sections.map(\.nameJapanese) == ["揚げ物", "焼き物"])
        #expect(bundle.items[0].sectionId == bundle.sections[0].id)
        #expect(bundle.items[2].sectionId == bundle.sections[0].id)
        #expect(bundle.items[1].description == "雞肉夾蔥")
    }
}

@Suite("ChatGPT 匯入：取代")
struct MenuImportReplaceTests {
    @Test("取代會丟掉舊菜單與原始照片，只留 ChatGPT 的內容")
    @MainActor
    func replaceDraft() {
        let store = MenuDraftStore(directory: nil)
        store.draft = MenuDraft(items: [MenuItemDraft(japaneseName: "舊的菜", priceText: "100")], otherLines: [MenuItemDraft(japaneseName: "雜訊")])
        let summary = store.replace(with: [
            .init(japaneseName: "若どり唐揚げ", chineseName: "日式炸嫩雞", price: 540, note: nil, section: "揚げ物"),
            .init(japaneseName: "手羽先", chineseName: "雞翅", price: 430, note: nil, section: nil),
        ])
        #expect(summary.total == 2)
        #expect(store.draft?.items.map(\.japaneseName) == ["若どり唐揚げ", "手羽先"])
        #expect(store.draft?.otherLines.isEmpty == true)
        #expect(store.sourceImages.isEmpty)
    }
}
