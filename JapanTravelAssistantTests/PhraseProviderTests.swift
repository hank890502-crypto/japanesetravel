import Testing
@testable import JapanTravelAssistant

@Suite("句子資料")
struct PhraseProviderTests {
    @Test("每個分類都有句子，且欄位不為空")
    func everyCategoryHasPhrases() async throws {
        let provider = BundledPhraseProvider()
        for category in PhraseCategory.allCases {
            let phrases = try await provider.phrases(in: category)
            #expect(!phrases.isEmpty, "\(category.displayName) 沒有句子")
            for phrase in phrases {
                #expect(!phrase.chinese.isEmpty)
                #expect(!phrase.japanese.isEmpty)
            }
        }
    }

    @Test("每個分類至少 4 個場面、25 句，且每句都有場面與讀音")
    func scenesAreRich() async throws {
        let provider = BundledPhraseProvider()
        for category in PhraseCategory.allCases {
            let phrases = try await provider.phrases(in: category)
            #expect(phrases.count >= 25, "\(category.displayName) 只有 \(phrases.count) 句")
            #expect(phrases.scenes.count >= 4, "\(category.displayName) 只有 \(phrases.scenes.count) 個場面")
            #expect(phrases.allSatisfy { $0.scene?.nilIfBlank != nil && $0.reading?.nilIfBlank != nil })
        }
        let hotel = try await provider.phrases(in: .hotel)
        #expect(hotel.scenes == ["入住", "住宿中", "客房服務", "早餐", "退房", "遇到問題"])
    }

    @Test("找商品用的問題都存在，且順序照指定")
    func findProductQuestionsExist() async throws {
        let ids = ["shop-have-this", "shop-where", "shop-stock", "shop-size", "shop-color", "shop-price"]
        let phrases = try await BundledPhraseProvider().phrases(ids: ids)
        #expect(phrases.map(\.id) == ids)
    }
}
