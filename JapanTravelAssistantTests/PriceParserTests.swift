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
}
