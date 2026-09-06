import Foundation
import Testing
@testable import JapanTravelAssistant

@Suite("Live Text 閱讀順序解析")
struct MenuTranscriptParserTests {
    @Test("漢數字")
    func kanjiNumbers() {
        #expect(KanjiNumberParser.parse("八四〇") == 840)
        #expect(KanjiNumberParser.parse("一一五〇") == 1150)
        #expect(KanjiNumberParser.parse("一一五O") == 1150)
        #expect(KanjiNumberParser.parse("千二百") == 1200)
        #expect(KanjiNumberParser.parse("一千二百") == 1200)
        #expect(KanjiNumberParser.parse("五百") == 500)
        #expect(KanjiNumberParser.parse("一万二千") == 12000)
        #expect(KanjiNumberParser.parse("二〇〇〇") == 2000)
        #expect(KanjiNumberParser.parse("定食") == nil)
        #expect(KanjiNumberParser.parse("十") == nil)
    }

    @Test("價格：漢數字、· 當 ¥、各、多組價格")
    func priceVariants() {
        #expect(PriceParser.priceOnly("八四〇円") == 840)
        #expect(PriceParser.priceOnly("一一五O円") == 1150)
        #expect(PriceParser.priceOnly("·540") == 540)
        #expect(PriceParser.split("【チューハイ】各520円").name == "チューハイ")
        #expect(PriceParser.split("【チューハイ】各520円").price == 520)
        let segments = PriceParser.splitAll("若どり唐揚げ ¥540 ねぎま 180円")
        #expect(segments.map(\.name) == ["若どり唐揚げ", "ねぎま"])
        #expect(segments.map(\.price) == [540, 180])
    }

    @Test("直排菜單（酒津屋）：Live Text 實際輸出")
    func verticalMenu() {
        let lines = ["味噌串カツ定食", "八四〇円", "エビカツ定食", "九七〇円", "みそカツ丼（大）", "一一五〇円", "トンカツ定食", "一一五〇円",
                     "味噌トンカツ定食", "一一五O円", "焼きそば", "五四〇円", "お好み焼き", "四八〇円", "ライス（小）", "一八〇円"]
        let result = MenuTranscriptParser.parse(lines: lines)
        #expect(result.items.map(\.name) == ["味噌串カツ定食", "エビカツ定食", "みそカツ丼（大）", "トンカツ定食", "味噌トンカツ定食", "焼きそば", "お好み焼き", "ライス（小）"])
        #expect(result.items.map(\.price) == [840, 970, 1150, 1150, 1150, 540, 480, 180])
        #expect(result.otherLines.isEmpty)
    }

    @Test("橫排兩欄菜單：Live Text 實際輸出（含空行與 · 當 ¥）")
    func horizontalMenu() {
        let lines = ["居酒屋 酒津屋", "揚げ物", "焼き物", "", "若どり唐揚げ", "·540", "ねぎま", "180円", "手羽先", "430円", "つくね", "¥200",
                     "味噌串カツ", "·540", "生ビール", "·650", "※価格は税込です"]
        let result = MenuTranscriptParser.parse(lines: lines)
        #expect(result.items.map(\.name) == ["若どり唐揚げ", "ねぎま", "手羽先", "つくね", "味噌串カツ", "生ビール"])
        #expect(result.items.map(\.price) == [540, 180, 430, 200, 540, 650])
        #expect(result.otherLines.map(\.name) == ["居酒屋 酒津屋", "揚げ物", "焼き物", "※価格は税込です"])
    }

    @Test("圖片式菜單（くら寿司）：品名兩行、括號補充、多語翻譯行")
    func pictureMenu() {
        let lines = [
            "〜お食事のおともに〜", "おつまみ・アルコール", "新登場",
            "豚軟骨うま煮", "(パイカ)", "420円", "Braised Pork Cartilage", "豬软骨 돼지 연골조림",
            "お刺身", "五種盛り", "(熟成まぐろ・サーモン・", "いくら・熟成真鯛・いか)", "580円", "※時期によって内容が変更", "Five Assorted Sashimi", "生魚片五種",
            "藁焼き", "かつおたたき", "460円", "Straw-grilled Bonito",
            "小海老の", "唐揚げ", "220円", "Fried Shrimps 炸小虾",
            "【スーパードライ(生)】", "650円",
            "【チューハイ】各520円", "プレーン・カルピス・レモン",
        ]
        let result = MenuTranscriptParser.parse(lines: lines)
        #expect(result.items.map(\.name) == ["豚軟骨うま煮(パイカ)", "お刺身五種盛り", "藁焼きかつおたたき", "小海老の唐揚げ", "スーパードライ(生)", "チューハイ"])
        #expect(result.items.map(\.price) == [420, 580, 460, 220, 650, 520])
        #expect(!result.otherLines.contains { $0.name.contains("Braised") })
        #expect(!result.otherLines.contains { $0.name.contains("生魚片") })
    }

    @Test("詞彙表翻譯")
    func glossary() {
        let glossary = MenuGlossary(entries: ["唐揚げ": "炸雞", "若どり": "嫩雞", "定食": "套餐", "手羽先": "雞翅", "生ビール": "生啤酒"])
        #expect(glossary.translate("若どり唐揚げ") == "嫩雞炸雞")
        #expect(glossary.translate("手羽先") == "雞翅")
        #expect(glossary.translate("生ビール（中）") == "生啤酒（中）")
        #expect(glossary.translate("ハイボール") == nil)
    }

    @Test("內建詞彙表可以載入且有內容")
    func bundledGlossaryLoads() {
        #expect(MenuGlossary.bundled.translate("唐揚げ") == "炸雞")
        #expect(MenuGlossary.bundled.translate("味噌串カツ定食") == "味噌炸串套餐")
    }
}
