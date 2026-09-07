import Foundation
import Testing
import UIKit
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

@Suite("ChatGPT 匯入：貼上整段對話、選項行歸屬")
struct MenuImportRobustnessTests {
    // B-30
    @Test("連提示文字一起貼回來也能匯入，且不會把提示裡的範例當成菜")
    func promptPastedTogetherWithReply() {
        let text = ChatGPTMenuPrompt.text + """


        好的，以下是翻譯：
        菜單開始
        分類 | 揚げ物 | 炸物
        若どり唐揚げ | 日式炸嫩雞 | 540 | 外酥內嫩 | wakadori karaage
        手羽先 | 雞翅 | 430 |
        分類 | 焼き物 | 烤物
        ねぎま | 蔥段雞肉串 | 180 |
        菜單結束
        """
        let items = MenuImportParser.parse(text)
        #expect(items.map(\.japaneseName) == ["若どり唐揚げ", "手羽先", "ねぎま"])
        #expect(items.map(\.section) == ["揚げ物", "揚げ物", "焼き物"])
        #expect(!items.contains { $0.japaneseName == "とんかつ" })
        #expect(items.allSatisfy { $0.options.isEmpty })
    }

    @Test("有兩組「菜單開始」：取有菜的那一組")
    func picksBlockWithItems() {
        let text = """
        菜單開始
        分類 | 日文分類名稱 | 繁體中文分類名稱
        日文原名 | 繁體中文翻譯 | 價格 | 一句簡短說明 | 羅馬拼音
        選項 | 選項群組 | 日文選項 | 中文選項 | 價差
        菜單結束

        菜單開始
        分類 | 揚げ物 | 炸物
        若どり唐揚げ | 日式炸嫩雞 | 540 |
        菜單結束
        """
        let items = MenuImportParser.parse(text)
        #expect(items.map(\.japaneseName) == ["若どり唐揚げ"])
        #expect(items[0].section == "揚げ物")
    }

    @Test("標記之間沒有菜時，退回整段文字解析")
    func fallsBackToWholeText() {
        let text = """
        菜單開始
        菜單結束
        若どり唐揚げ | 日式炸嫩雞 | 540 |
        """
        #expect(MenuImportParser.parse(text).map(\.japaneseName) == ["若どり唐揚げ"])
    }

    // B-31
    @Test("選項只掛在「前一行就是那道菜」的情況；漏了分隔線的菜用價格解析")
    func optionsAttachOnlyToPreviousItem() {
        let text = """
        手羽先 | 雞翅 | 430
        とんかつ 540円
        選項 | 份量 | 大盛り | 大份 | +150
        分類 | ドリンク | 飲料
        選項 | 份量 | 大 | 大杯 | +100
        生ビール | 生啤酒 | 650
        選項 | 份量 | 中 | 中杯 | 0
        """
        let items = MenuImportParser.parse(text)
        #expect(items.map(\.japaneseName) == ["手羽先", "とんかつ", "生ビール"])
        #expect(items[0].options.isEmpty)
        #expect(items[1].price == 540)
        #expect(items[1].options.map(\.japaneseName) == ["大盛り"])
        #expect(items[2].section == "ドリンク")
        #expect(items[2].options.map(\.japaneseName) == ["中"])   // 分類行後的孤兒選項「大」被忽略
    }

    @Test("沒有價格標記的單欄閒聊句不會變成菜")
    func singleFieldChatterIgnored() {
        let text = """
        好的，以下是翻譯結果
        手羽先 | 雞翅 | 430
        希望對你有幫助 2024
        """
        #expect(MenuImportParser.parse(text).map(\.japaneseName) == ["手羽先"])
    }
}

@Suite("匯入合併：子字串配對與保留使用者修改")
struct MenuMergeTests {
    // B-29 (a)
    @Test("草稿有「とんかつ定食」與「とんかつ」：兩筆各自更新、順序不變")
    @MainActor
    func substringPairsResolveExactFirst() {
        let store = MenuDraftStore(directory: nil)
        store.draft = MenuDraft(items: [
            MenuItemDraft(japaneseName: "とんかつ定食", priceText: ""),
            MenuItemDraft(japaneseName: "とんかつ", priceText: ""),
        ])
        let summary = store.merge(imported: [
            .init(japaneseName: "とんかつ", chineseName: "炸豬排", price: 540, note: nil, section: "揚げ物"),
            .init(japaneseName: "とんかつ定食", chineseName: "炸豬排套餐", price: 900, note: nil, section: "定食"),
        ])
        #expect(summary.updated == 2)
        #expect(summary.added == 0)
        let items = store.draft!.items
        #expect(items.map(\.japaneseName) == ["とんかつ定食", "とんかつ"])
        #expect(items.map(\.chineseName) == ["炸豬排套餐", "炸豬排"])
        #expect(items.map(\.priceText) == ["900", "540"])
        #expect(items.map(\.sectionName) == ["定食", "揚げ物"])
    }

    // B-29 (b)
    @Test("草稿只有「唐揚げ」：匯入的三種唐揚げ不會全部併進同一道")
    @MainActor
    func substringMatchUsedOnlyOnce() {
        let store = MenuDraftStore(directory: nil)
        store.draft = MenuDraft(items: [MenuItemDraft(japaneseName: "唐揚げ", priceText: "380")])
        let summary = store.merge(imported: [
            .init(japaneseName: "鶏唐揚げ", chineseName: "炸雞", price: 540, note: nil, section: nil),
            .init(japaneseName: "タコ唐揚げ", chineseName: "炸章魚", price: 480, note: nil, section: nil),
        ])
        #expect(summary.updated <= 1)
        #expect(summary.added >= 1)
        #expect(store.draft!.items.count == 2)
        // 子字串配對時保留使用者現有的日文寫法
        #expect(store.draft!.items[0].japaneseName == "唐揚げ")
        #expect(store.draft!.items[0].chineseName == "炸雞")
        #expect(store.draft!.items[1].japaneseName == "タコ唐揚げ")
    }

    // B-29：finding #22 的情境
    @Test("草稿有「唐揚げ」與「若どり唐揚げ」：各自拿到自己的中文與價格")
    @MainActor
    func bothSubstringDishesUpdated() {
        let store = MenuDraftStore(directory: nil)
        store.draft = MenuDraft(items: [
            MenuItemDraft(japaneseName: "唐揚げ"),
            MenuItemDraft(japaneseName: "若どり唐揚げ"),
        ])
        let summary = store.merge(imported: [
            .init(japaneseName: "若どり唐揚げ", chineseName: "炸嫩雞", price: 540, note: nil, section: nil),
            .init(japaneseName: "唐揚げ", chineseName: "炸雞", price: 380, note: nil, section: nil),
        ])
        #expect(summary.updated == 2)
        let items = store.draft!.items
        #expect(items.map(\.chineseName) == ["炸雞", "炸嫩雞"])
        #expect(items.map(\.priceText) == ["380", "540"])
    }

    @Test("完全相符優先於子字串：先出現的短名字不會搶走長名字的那道菜")
    @MainActor
    func exactMatchBeatsEarlierSubstring() {
        let store = MenuDraftStore(directory: nil)
        store.draft = MenuDraft(items: [MenuItemDraft(japaneseName: "若どり唐揚げ")])
        let summary = store.merge(imported: [
            .init(japaneseName: "唐揚げ", chineseName: "炸雞", price: 380, note: nil, section: nil),
            .init(japaneseName: "若どり唐揚げ", chineseName: "炸嫩雞", price: 540, note: nil, section: nil),
        ])
        #expect(summary.updated == 1)
        #expect(summary.added == 1)
        #expect(store.draft!.items[0].chineseName == "炸嫩雞")
        #expect(store.draft!.items[1].japaneseName == "唐揚げ")
    }

    @Test("OCR 漏字（手先 → 手羽先）仍能用子字串配到")
    @MainActor
    func ocrMissingCharacterStillMatches() {
        let store = MenuDraftStore(directory: nil)
        store.draft = MenuDraft(items: [MenuItemDraft(japaneseName: "手羽先", priceText: "430")])
        let summary = store.merge(imported: [.init(japaneseName: "手羽先唐揚げ", chineseName: "炸雞翅", price: 430, note: nil, section: nil)])
        #expect(summary.updated == 1)
        #expect(store.draft!.items[0].chineseName == "炸雞翅")
        #expect(store.draft!.items[0].japaneseName == "手羽先")
    }

    // B-34
    @Test("補進模式：使用者改過的名稱、中文、價格、分類、選項全部保留，只填空的")
    @MainActor
    func fillMissingKeepsUserEdits() {
        let store = MenuDraftStore(directory: nil)
        store.draft = MenuDraft(items: [
            MenuItemDraft(japaneseName: "とんかつ", chineseName: "我的炸豬排", priceText: "540", sectionName: "主菜", options: [
                MenuOptionDraft(groupName: "份量", japaneseName: "大盛り", chineseName: "大份", priceDeltaText: "+150"),
            ]),
            MenuItemDraft(japaneseName: "手羽先", priceText: ""),
        ], sectionChineseNames: ["主菜": "我的主菜"])
        let summary = store.merge(imported: [
            .init(japaneseName: "とんかつ", chineseName: "AI 炸豬排", price: 999, note: "AI 說明", section: "揚げ物", sectionChinese: "炸物",
                  options: [.init(groupName: "套餐", japaneseName: "定食", chineseName: "定食", priceDelta: 300)], reading: "tonkatsu"),
            .init(japaneseName: "手羽先", chineseName: "雞翅", price: 430, note: nil, section: "揚げ物", sectionChinese: "炸物"),
            .init(japaneseName: "ねぎま", chineseName: "蔥雞串", price: 180, note: nil, section: "焼き物"),
        ], mode: .fillMissing)
        #expect(summary.updated == 2)
        #expect(summary.added == 1)
        let tonkatsu = store.draft!.items[0]
        #expect(tonkatsu.chineseName == "我的炸豬排")
        #expect(tonkatsu.priceText == "540")
        #expect(tonkatsu.sectionName == "主菜")
        #expect(tonkatsu.options.map(\.japaneseName) == ["大盛り"])
        #expect(tonkatsu.note == "AI 說明")          // 原本空的欄位才補
        #expect(tonkatsu.reading == "tonkatsu")
        let tebasaki = store.draft!.items[1]
        #expect(tebasaki.chineseName == "雞翅")
        #expect(tebasaki.priceText == "430")
        #expect(tebasaki.sectionName == "揚げ物")
        #expect(store.draft!.sectionChineseNames["主菜"] == "我的主菜")
        #expect(store.draft!.sectionChineseNames["揚げ物"] == "炸物")
        #expect(store.draft!.items[2].japaneseName == "ねぎま")
    }

    @Test("覆蓋模式（ChatGPT 補進）維持原本行為：匯入的中文與價格優先")
    @MainActor
    func overwriteModeUpdatesFields() {
        let store = MenuDraftStore(directory: nil)
        store.draft = MenuDraft(items: [MenuItemDraft(japaneseName: "とんかつ", chineseName: "舊", priceText: "500")])
        store.merge(imported: [.init(japaneseName: "とんかつ", chineseName: "炸豬排", price: 540, note: nil, section: nil)])
        #expect(store.draft!.items[0].chineseName == "炸豬排")
        #expect(store.draft!.items[0].priceText == "540")
    }
}

@Suite("草稿：加入另一面菜單、其他文字延後加入")
struct MenuDraftAppendTests {
    // B-35
    @Test("append 會保留原本的菜與修改，只加新的，重複的不加，照片接在後面")
    @MainActor
    func appendKeepsExistingDraft() {
        let store = MenuDraftStore(directory: nil)
        store.startNew(items: [MenuItemDraft(japaneseName: "唐揚げ", chineseName: "我改過的炸雞", priceText: "540")],
                       otherLines: [MenuItemDraft(japaneseName: "居酒屋 酒津屋")],
                       images: [UIImage()])
        store.append(items: [MenuItemDraft(japaneseName: "唐揚げ", priceText: "999"), MenuItemDraft(japaneseName: "ねぎま", priceText: "180")],
                     otherLines: [MenuItemDraft(japaneseName: "居酒屋 酒津屋"), MenuItemDraft(japaneseName: "※税込")],
                     images: [UIImage()])
        let draft = store.draft!
        #expect(draft.items.map(\.japaneseName) == ["唐揚げ", "ねぎま"])
        #expect(draft.items[0].chineseName == "我改過的炸雞")
        #expect(draft.items[0].priceText == "540")
        #expect(draft.otherLines.map(\.japaneseName) == ["居酒屋 酒津屋", "※税込"])
        #expect(store.sourceImages.count == 2)
    }

    @Test("沒有草稿時 append 等同新建")
    @MainActor
    func appendWithoutDraftStartsNew() {
        let store = MenuDraftStore(directory: nil)
        store.append(items: [MenuItemDraft(japaneseName: "唐揚げ")], otherLines: [], images: [])
        #expect(store.draft?.items.map(\.japaneseName) == ["唐揚げ"])
    }

    // B-39
    @Test("其他文字按「加入」後按「取消」不會動；按「儲存」才移進菜單")
    @MainActor
    func promoteOnlyOnSave() {
        let store = MenuDraftStore(directory: nil)
        let line = MenuItemDraft(japaneseName: "店名っぽい行")
        store.draft = MenuDraft(items: [], otherLines: [line])

        // 取消：畫面不呼叫任何 store 方法 → 原樣
        #expect(store.draft!.items.isEmpty)
        #expect(store.draft!.otherLines.count == 1)

        // 儲存：移進菜單並套用使用者改的內容
        var edited = line
        edited.priceText = "300"
        store.promoteOtherLine(edited)
        #expect(store.draft!.items.map(\.japaneseName) == ["店名っぽい行"])
        #expect(store.draft!.items[0].priceText == "300")
        #expect(store.draft!.otherLines.isEmpty)
    }
}

@Suite("ChatGPT 匯入：取代")
struct MenuImportReplaceTests {
    @Test("AI 換成新菜單時保留原始照片與店名")
    @MainActor
    func replaceKeepingImages() {
        let store = MenuDraftStore(directory: nil)
        store.startNew(items: [MenuItemDraft(japaneseName: "舊的菜")], images: [UIImage()])
        store.draft?.restaurantName = "酒津屋"
        store.replace(with: [.init(japaneseName: "唐揚げ", chineseName: "炸雞", price: 540, note: nil, section: nil)], keepingImages: true)
        #expect(store.draft?.items.map(\.japaneseName) == ["唐揚げ"])
        #expect(store.draft?.restaurantName == "酒津屋")
        #expect(store.sourceImages.count == 1)
    }

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
