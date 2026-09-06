import Foundation
import Testing
@testable import JapanTravelAssistant

@Suite("菜單分類")
struct MenuSectionTests {
    @Test("辨識到分類標題時，後面的菜自動歸類")
    func transcriptAssignsSections() {
        let lines = ["揚げ物", "若どり唐揚げ", "¥540", "手羽先", "430円", "ドリンク", "生ビール", "¥650", "ウーロン茶", "¥300"]
        let result = MenuTranscriptParser.parse(lines: lines)
        #expect(result.items.map(\.section) == ["揚げ物", "揚げ物", "ドリンク", "ドリンク"])
        #expect(result.otherLines.isEmpty)
    }

    @Test("ChatGPT 的「## 日文 | 中文」分類會帶中文名稱")
    func importParsesSectionChinese() {
        let text = """
        菜單開始
        ## 揚げ物 | 炸物
        若どり唐揚げ | 日式炸嫩雞 | 540 |
        ## ドリンク | 飲料
        生ビール | 生啤酒 | 650 |
        菜單結束
        """
        let items = MenuImportParser.parse(text)
        #expect(items.map(\.section) == ["揚げ物", "ドリンク"])
        #expect(items.map(\.sectionChinese) == ["炸物", "飲料"])
    }

    @Test("分組：依出現順序，沒有分類的放最後；正式菜單帶中文分類名")
    @MainActor
    func groupingAndBundle() {
        let store = MenuDraftStore(directory: nil)
        store.replace(with: [
            .init(japaneseName: "生ビール", chineseName: "生啤酒", price: 650, note: nil, section: "ドリンク", sectionChinese: "飲料"),
            .init(japaneseName: "若どり唐揚げ", chineseName: "炸雞", price: 540, note: nil, section: "揚げ物", sectionChinese: "炸物"),
            .init(japaneseName: "お通し", chineseName: "小菜", price: 300, note: nil, section: nil),
            .init(japaneseName: "手羽先", chineseName: "雞翅", price: 430, note: nil, section: "揚げ物", sectionChinese: nil),
        ])
        let groups = store.draft!.groupedItems
        #expect(groups.map(\.section) == ["ドリンク", "揚げ物", nil])
        #expect(groups[1].items.map(\.japaneseName) == ["若どり唐揚げ", "手羽先"])
        #expect(groups[1].sectionChinese == "炸物")

        let bundle = store.draft!.toBundle()
        #expect(bundle.sections.map(\.nameJapanese) == ["ドリンク", "揚げ物"])
        #expect(bundle.sections.map(\.nameChinese) == ["飲料", "炸物"])
        #expect(bundle.items.first { $0.japaneseName == "お通し" }?.sectionId == nil)
    }

    @Test("舊草稿沒有 sectionChineseNames 也能讀")
    func legacyDecode() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","restaurantName":"","items":[],"otherLines":[],"createdAt":0}"#
        let draft = try JSONDecoder().decode(MenuDraft.self, from: Data(json.utf8))
        #expect(draft.sectionChineseNames.isEmpty)
    }
}
