import Foundation
import Testing
@testable import JapanTravelAssistant

@Suite("價格文字轉數字（匯入與手動輸入）")
struct PriceFormatterTests {
    private func int(_ value: Decimal?) -> Int? {
        value.map { NSDecimalNumber(decimal: $0).intValue }
    }

    // B-28：多段數字不能黏在一起
    @Test("只取一個數字，不把多段數字拼接", arguments: [
        ("540〜800", 540),
        ("540~800", 540),
        ("¥500/1個", 500),
        ("1,200", 1200),
        ("1,200 (大 1,500)", 1200),
        ("S 400 / M 500", 400),
        ("540円 大800", 540),
        ("￥５４０", 540),
        ("¥540", 540),
        ("650円", 650),
        ("540", 540),
    ])
    func takesFirstNumber(text: String, expected: Int) {
        #expect(int(PriceFormatter.parse(text)) == expected, Comment(rawValue: text))
    }

    @Test("有税込就取税込的那個")
    func taxIncludedWins() {
        #expect(int(PriceFormatter.parse("380円（税込418円）")) == 418)
        #expect(int(PriceFormatter.parse("540円（税込594円）")) == 594)
        #expect(int(PriceFormatter.parse("税込 594")) == 594)
    }

    @Test("沒有數字就 nil", arguments: ["時価", "", "  ", "ASK", "無料"])
    func noNumber(text: String) {
        #expect(PriceFormatter.parse(text) == nil, Comment(rawValue: text))
    }

    @Test("草稿的價格用同一套規則")
    func draftPrice() {
        #expect(int(MenuItemDraft(japaneseName: "唐揚げ", priceText: "540〜800").price) == 540)
        #expect(int(MenuItemDraft(japaneseName: "枝豆", priceText: "380円（税込418円）").price) == 418)
        #expect(MenuItemDraft(japaneseName: "時価の魚", priceText: "時価").price == nil)
    }

    @Test("價差解析不受影響")
    func deltaStillWorks() {
        #expect(int(PriceFormatter.parseDelta("+150")) == 150)
        #expect(int(PriceFormatter.parseDelta("-100")) == -100)
        #expect(int(PriceFormatter.parseDelta("±0")) == 0)
        #expect(int(PriceFormatter.parseDelta("+¥1,200")) == 1200)
        #expect(PriceFormatter.parseDelta("abc") == nil)
    }
}
