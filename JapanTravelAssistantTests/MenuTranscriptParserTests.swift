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

    // MARK: - B-32：單字條目不能在多字詞裡逐字套用

    @Test("單字條目只用於完全相符，不會產生「雞雞皮」")
    func singleCharacterEntriesOnlyExact() {
        let glossary = MenuGlossary(entries: ["鶏": "雞", "皮": "雞皮", "天": "天婦羅", "刺": "生魚片", "鯛": "鯛魚", "焼": "烤", "売": "賣"])
        #expect(glossary.translate("皮") == "雞皮")            // 完全相符仍可用
        #expect(glossary.translate("鶏皮") == nil)             // 不逐字拼成「雞雞皮」，交給系統翻譯
        #expect(glossary.translate("天然鯛") == nil)
        #expect(glossary.translate("焼売") == nil)
        // 所有單字條目在多字詞裡都不會被單獨套用（尺寸的 大／中／小／並 除外）
        for key in ["鶏", "皮", "天", "刺", "鯛", "焼", "売"] {
            let translated = glossary.translate("\(key)テスト")
            #expect(translated == nil || translated == "\(key)テスト", Comment(rawValue: key))
        }
    }

    @Test("內建詞彙表：鶏皮、焼売、中華そば、天然鯛、刺し盛り")
    func bundledGlossaryNoCharacterByCharacter() {
        let bundled = MenuGlossary.bundled
        #expect(bundled.translate("鶏皮") == "雞皮")
        #expect(bundled.translate("鶏皮ポン酢") == "雞皮柚子醋")
        #expect(bundled.translate("焼売") == "燒賣")
        #expect(bundled.translate("中華そば")?.contains("拉麵") == true)
        #expect(bundled.translate("天然鯛")?.contains("天婦羅") != true)
        #expect(bundled.translate("刺し盛り")?.contains("し") != true)
        #expect(bundled.translate("生姜焼き") == "薑燒豬肉")
        #expect(bundled.translate("水餃子") == "水餃")
        #expect(bundled.translate("ライス（小）") == "白飯（小）")
        #expect(bundled.translate("カレー（並）") == "咖哩（普通）")
    }
}

@Suite("Live Text 解析：分類詞、括號、尺寸、欄式順序")
struct MenuTranscriptParserRegressionTests {
    // B-23
    @Test("也可能是菜名的分類詞後面直接接價格 → 一道菜")
    func ambiguousHeaderFollowedByPriceIsItem() {
        let result = MenuTranscriptParser.parse(lines: ["ラーメン", "800円"])
        #expect(result.items.map(\.name) == ["ラーメン"])
        #expect(result.items.map(\.price) == [800])
        #expect(result.otherLines.isEmpty)
    }

    @Test("拉麵店直排菜單：ラーメン、ライス 都是菜")
    func ramenShopVerticalMenu() {
        let result = MenuTranscriptParser.parse(lines: ["ラーメン", "800円", "チャーシューメン", "1000円", "ライス", "150円"])
        #expect(result.items.map(\.name) == ["ラーメン", "チャーシューメン", "ライス"])
        #expect(result.items.map(\.price) == [800, 1000, 150])
        #expect(result.items.map(\.section) == [nil, nil, nil])
        #expect(result.otherLines.isEmpty)
    }

    @Test("居酒屋飲料：ビール／ハイボール 直接接價格")
    func drinksFollowedByPrice() {
        let result = MenuTranscriptParser.parse(lines: ["ビール", "500円", "ハイボール", "450円"])
        #expect(result.items.map(\.name) == ["ビール", "ハイボール"])
        #expect(result.items.map(\.price) == [500, 450])
    }

    @Test("同一個詞後面接的是菜名（沒價格）時仍是分類")
    func ambiguousHeaderFollowedByNameIsSection() {
        let result = MenuTranscriptParser.parse(lines: ["ビール", "生ビール", "650円", "瓶ビール", "700円", "ライス", "白ご飯", "200円"])
        #expect(result.items.map(\.name) == ["生ビール", "瓶ビール", "白ご飯"])
        #expect(result.items.map(\.section) == ["ビール", "ビール", "ライス"])
        #expect(result.otherLines.isEmpty)
    }

    @Test("純分類詞維持原本行為（揚げ物／ドリンク）")
    func pureHeadersUnchanged() {
        let result = MenuTranscriptParser.parse(lines: ["揚げ物", "若どり唐揚げ", "¥540", "ドリンク", "生ビール", "¥650"])
        #expect(result.items.map(\.section) == ["揚げ物", "ドリンク"])
        #expect(MenuTranscriptParser.isSectionHeader("ラーメン"))
        #expect(MenuTranscriptParser.isSectionHeader("揚げ物"))
        #expect(MenuTranscriptParser.pureSectionHeaders.isDisjoint(with: MenuTranscriptParser.ambiguousSectionHeaders))
    }

    // B-24
    @Test("※ 開頭的税込備註就算含 10% 也不是菜")
    func taxRemarkWithPercentIsNotItem() {
        let result = MenuTranscriptParser.parse(lines: ["枝豆", "380円", "※表示価格は税込（消費税10%）です", "唐揚げ", "540円"])
        #expect(result.items.map(\.name) == ["枝豆", "唐揚げ"])
        #expect(result.items.map(\.price) == [380, 540])
        #expect(result.otherLines.map(\.name) == ["※表示価格は税込（消費税10%）です"])
    }

    // B-25
    @Test("店家資訊行不會變成菜")
    func storeInfoLinesAreOtherText() {
        // 純英文的 TEL 行本來就會被當成外文略過（後面只有漢字的行也會被當成它的中文翻譯），
        // 所以放在最後；含漢字的店家資訊進其他文字
        let result = MenuTranscriptParser.parse(lines: ["唐揚げ", "540円", "電話 052-123-4567", "営業時間 11:30〜23:30", "〒460-0008 名古屋市中区栄3-12", "TEL 052-123-4567"])
        #expect(result.items.map(\.name) == ["唐揚げ"])
        #expect(result.items.map(\.price) == [540])
        #expect(result.otherLines.map(\.name) == ["電話 052-123-4567", "営業時間 11:30〜23:30", "〒460-0008 名古屋市中区栄3-12"])
    }

    // B-26
    @Test("OCR 漏掉右括號：遇到價格就結束說明，後面的菜照常解析")
    func unclosedParenthesisEndsAtPrice() {
        let lines = ["お刺身", "五種盛り", "(熟成まぐろ・サーモン・", "いくら・熟成真鯛・いか", "580円", "藁焼き", "かつおたたき", "460円", "小海老の", "唐揚げ", "220円"]
        let result = MenuTranscriptParser.parse(lines: lines)
        #expect(result.items.map(\.name) == ["お刺身五種盛り", "藁焼きかつおたたき", "小海老の唐揚げ"])
        #expect(result.items.map(\.price) == [580, 460, 220])
    }

    @Test("括號說明最多跳 3 行，之後照常解析")
    func unclosedParenthesisHasLineLimit() {
        let lines = ["(季節の野菜を使った", "自慢の一品です", "本日のおすすめです", "ぜひどうぞ", "ほうれん草のおひたし", "唐揚げ", "540円"]
        let result = MenuTranscriptParser.parse(lines: lines)
        #expect(result.items.map(\.name) == ["唐揚げ"])
        #expect(result.items.map(\.price) == [540])
    }

    @Test("括號正常關閉的情況不變")
    func closedParenthesisStillSkipped() {
        let lines = ["お刺身", "五種盛り", "(熟成まぐろ・サーモン・", "いくら・熟成真鯛・いか)", "580円"]
        let result = MenuTranscriptParser.parse(lines: lines)
        #expect(result.items.map(\.name) == ["お刺身五種盛り"])
        #expect(result.items.map(\.price) == [580])
    }

    // B-27
    @Test("「並／大」尺寸價格行：品名是上一行的菜 + 尺寸")
    func sizeLinesUsePreviousName() {
        let result = MenuTranscriptParser.parse(lines: ["カレー", "並 600円", "大 800円", "カツカレー", "並 900円"])
        #expect(result.items.map(\.name) == ["カレー（並）", "カレー（大）", "カツカレー（並）"])
        #expect(result.items.map(\.price) == [600, 800, 900])
        #expect(result.otherLines.isEmpty)
    }

    @Test("尺寸自己一行（直排）、括號尺寸、S/M/L")
    func sizeVariants() {
        let vertical = MenuTranscriptParser.parse(lines: ["ラーメン", "並", "800円", "大", "900円"])
        #expect(vertical.items.map(\.name) == ["ラーメン（並）", "ラーメン（大）"])
        #expect(vertical.items.map(\.price) == [800, 900])

        let parens = MenuTranscriptParser.parse(lines: ["カレー", "(大) 800円"])
        #expect(parens.items.map(\.name) == ["カレー（大）"])

        let sml = MenuTranscriptParser.parse(lines: ["ドリンク", "コーラ", "S 200円", "M 250円", "L 300円"])
        #expect(sml.items.map(\.name) == ["コーラ（S）", "コーラ（M）", "コーラ（L）"])
        #expect(sml.items.map(\.section) == ["ドリンク", "ドリンク", "ドリンク"])
    }

    @Test("尺寸行之後出現一般的菜，不會再沿用前面的品名")
    func sizeBaseResetsOnNextDish() {
        let result = MenuTranscriptParser.parse(lines: ["カレー", "並 600円", "ライス 150円", "大 800円"])
        #expect(result.items.map(\.name) == ["カレー（並）", "ライス", "大"])
    }

    // B-37
    @Test("先一欄品名再一欄價格：依序配對")
    func columnReadingOrder() {
        let lines = ["若どり唐揚げ", "手羽先", "味噌串カツ", "ねぎま", "¥540", "¥430", "¥540", "¥180"]
        let result = MenuTranscriptParser.parse(lines: lines)
        #expect(result.items.map(\.name) == ["若どり唐揚げ", "手羽先", "味噌串カツ", "ねぎま"])
        #expect(result.items.map(\.price) == [540, 430, 540, 180])
        #expect(result.otherLines.isEmpty)
    }

    @Test("欄式順序前面多出店名：只配最後 N 行，店名進其他文字")
    func columnReadingOrderWithExtraName() {
        let lines = ["居酒屋 酒津屋", "揚げ物", "若どり唐揚げ", "手羽先", "味噌串カツ", "¥540", "¥430", "¥540"]
        let result = MenuTranscriptParser.parse(lines: lines)
        #expect(result.items.map(\.name) == ["若どり唐揚げ", "手羽先", "味噌串カツ"])
        #expect(result.items.map(\.price) == [540, 430, 540])
        #expect(result.items.map(\.section) == ["揚げ物", "揚げ物", "揚げ物"])
        #expect(result.otherLines.map(\.name) == ["居酒屋 酒津屋"])
    }

    @Test("連續兩個價格（同一道菜兩種份量）不會被當成欄式順序")
    func twoPricesInARowAreNotColumns() {
        #expect(MenuTranscriptParser.interleaveColumns(["ライス", "180円", "250円"]) == ["ライス", "180円", "250円"])
        #expect(MenuTranscriptParser.interleaveColumns(["a", "b", "¥1", "¥2", "¥3"]) == ["a", "b", "¥1", "¥2", "¥3"])
    }
}

@Suite("辨識引擎：Live Text 與 Vision 的取捨")
struct MenuRecognitionDecisionTests {
    private func candidate(_ name: String, price: Decimal? = nil) -> MenuCandidate {
        MenuCandidate(name: name, price: price, confidence: 0.9, sourceText: name)
    }

    @Test("Live Text 配不出菜、或價格行比菜多時才退回 Vision")
    func fallbackDecision() {
        let none = MenuParseResult(items: [], otherLines: [candidate("居酒屋"), candidate("¥540")])
        #expect(LiveMenuRecognitionService.shouldFallBackToVision(none))

        let underPaired = MenuParseResult(items: [candidate("ねぎま", price: 540)], otherLines: [candidate("若どり唐揚げ"), candidate("¥430"), candidate("¥540"), candidate("¥180")])
        #expect(LiveMenuRecognitionService.shouldFallBackToVision(underPaired))

        let good = MenuParseResult(items: [candidate("若どり唐揚げ", price: 540), candidate("手羽先", price: 430)], otherLines: [candidate("居酒屋"), candidate("※税込")])
        #expect(!LiveMenuRecognitionService.shouldFallBackToVision(good))
    }

    @Test("取菜比較多的那份；一樣多以 Live Text 為準")
    func preferMoreItems() {
        let live = MenuParseResult(items: [candidate("A", price: 1)], otherLines: [])
        let vision = MenuParseResult(items: [candidate("A", price: 1), candidate("B", price: 2)], otherLines: [])
        #expect(LiveMenuRecognitionService.preferred(liveText: live, vision: vision).items.count == 2)
        #expect(LiveMenuRecognitionService.preferred(liveText: vision, vision: vision) == vision)
        #expect(LiveMenuRecognitionService.preferred(liveText: nil, vision: vision) == vision)
        let tie = MenuParseResult(items: [candidate("X", price: 3)], otherLines: [])
        #expect(LiveMenuRecognitionService.preferred(liveText: live, vision: tie) == live)
    }
}
