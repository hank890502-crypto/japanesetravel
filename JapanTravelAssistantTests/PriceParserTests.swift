import Foundation
import Testing
@testable import JapanTravelAssistant

@Suite("價格解析")
struct PriceParserTests {
    @Test(arguments: [
        ("若どり唐揚げ ¥540", "若どり唐揚げ", 540),
        ("手羽先 430円", "手羽先", 430),
        ("味噌串カツ　￥１，２００", "味噌串カツ", 1200),
        ("生ビール 650", "生ビール", 650),
        ("枝豆 ¥1,200", "枝豆", 1200),
        ("枝豆 税込418円", "枝豆", 418),
        ("枝豆 税込 ¥418", "枝豆", 418),
        ("枝豆 税込418", "枝豆", 418),
        ("唐揚げ 540（税込）", "唐揚げ", 540),
        ("生ビール 500 税込", "生ビール", 500),
    ])
    func splitsNameAndPrice(line: String, name: String, price: Int) {
        let result = PriceParser.split(line)
        #expect(result.name == name)
        #expect(result.price == Decimal(price))
    }

    @Test("沒有價格時品名原樣、價格 nil")
    func noPrice() {
        let result = PriceParser.split("本日のおすすめ")
        #expect(result.name == "本日のおすすめ")
        #expect(result.price == nil)
    }

    // B-25：電話、年份、日期、時間、人數、郵遞區號、地址都不是價格
    @Test("店家資訊行的行尾數字不是價格", arguments: [
        "TEL 052-123-4567",
        "☎ 052-123-4567",
        "ご予約 TEL 052-123-4567",
        "お席 2名様〜 予約 090-1234-5678",
        "2024年10月改定 2024",
        "2024年",
        "10/12",
        "営業時間 11:30〜23:30",
        "11:30〜14:00",
        "L.O. 22:30",
        "2名様",
        "〒460-0008",
        "名古屋市中区栄3-12",
        "税込価格 2024年改定",
        "税込表示 2024",
    ])
    func storeInfoIsNotPrice(line: String) {
        #expect(PriceParser.split(line).price == nil, Comment(rawValue: line))
        #expect(PriceParser.priceOnly(line) == nil, Comment(rawValue: line))
    }

    // B-24：「税込」後面的百分比、年份不是價格
    @Test("税込備註裡的 10% 不是價格", arguments: [
        "※表示価格は税込（消費税10%）です",
        "※全て税込価格 10%対象",
        "税込 10%",
    ])
    func taxRemarkIsNotPrice(line: String) {
        #expect(PriceParser.priceOnly(line) == nil, Comment(rawValue: line))
        #expect(PriceParser.splitAll(line).allSatisfy { $0.price == nil }, Comment(rawValue: line))
    }

    @Test("税込價仍然優先")
    func taxIncludedStillWins() {
        #expect(PriceParser.priceOnly("税込594円") == 594)
        #expect(PriceParser.priceOnly("（税込594円）") == 594)
        #expect(PriceParser.split("枝豆 380円（税込418円）").price == 418)
        #expect(PriceParser.split("枝豆 380円（税込418円）").name == "枝豆")
    }

    // B-33：品名開頭／結尾的「各」是品名的一部分
    @Test("「各」只在價格前面才拿掉")
    func kakuStaysInName() {
        #expect(PriceParser.split("各種サワー 450円").name == "各種サワー")
        #expect(PriceParser.split("各種サワー 450円").price == 450)
        #expect(PriceParser.split("各種サラダ 380円").name == "各種サラダ")
        #expect(PriceParser.split("各種ソフトドリンク 300円").name == "各種ソフトドリンク")
        #expect(PriceParser.split("サラダ各種").name == "サラダ各種")
        #expect(PriceParser.cleanName("各種サラダ") == "各種サラダ")
        #expect(PriceParser.split("【チューハイ】各520円").name == "チューハイ")
        #expect(PriceParser.split("【チューハイ】各520円").price == 520)
        #expect(PriceParser.priceOnly("各520円") == 520)
    }
}
