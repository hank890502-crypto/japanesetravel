import Testing
@testable import JapanTravelAssistant

@Suite("羅馬拼音")
struct JapaneseReadingTests {
    @Test("iOS 斷詞器可以離線產生拼音")
    func romaji() {
        #expect(JapaneseReading.romaji(for: "とんかつ")?.lowercased() == "tonkatsu")
        #expect(JapaneseReading.romaji(for: "唐揚げ")?.lowercased().replacingOccurrences(of: " ", with: "") == "karaage")
        let beer = JapaneseReading.romaji(for: "生ビール")?.lowercased().replacingOccurrences(of: " ", with: "") ?? ""
        #expect(beer.contains("nama") && beer.contains("b"), Comment(rawValue: beer))
        #expect(JapaneseReading.romaji(for: "Coca Cola") == nil)
        #expect(JapaneseReading.hiragana(for: "唐揚げ")?.replacingOccurrences(of: " ", with: "") == "からあげ")
    }

    @Test("ChatGPT 給的第 5 欄拼音會被讀進來")
    func importReading() {
        let items = MenuImportParser.parse("とんかつ | 炸豬排 | 540 | 酥脆 | tonkatsu")
        #expect(items.first?.reading == "tonkatsu")
    }
}
