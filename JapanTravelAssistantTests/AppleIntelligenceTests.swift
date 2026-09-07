import Foundation
import Testing
@testable import JapanTravelAssistant

/// 真的呼叫 Apple 智慧（需要模擬器／裝置支援且已開啟）。不支援時整個跳過。
@Suite("Apple 智慧（需要支援的裝置）")
struct AppleIntelligenceTests {
    @Test("規則修正：分類標題不算菜、選項對回同一行的菜")
    func cleanUpRules() {
        guard #available(iOS 26, *) else { return }
        let lines = ["揚げ物", "若どり唐揚げ ¥540", "とんかつ 540円 大盛り +150円", "ドリンク", "生ビール ¥650"]
        let large = MenuAnalysis.OptionDraft(groupName: "份量", japaneseName: "大盛り", chineseName: "大份", priceDelta: 150)
        let items = [
            MenuAnalysis.ItemDraft(japaneseName: "若どり唐揚げ", chineseName: "炸雞", reading: nil, price: 540, sectionName: "揚げ物", options: [large], confidence: nil),
            MenuAnalysis.ItemDraft(japaneseName: "とんかつ", chineseName: "炸豬排", reading: nil, price: 540, sectionName: "揚げ物", confidence: nil),
            MenuAnalysis.ItemDraft(japaneseName: "ドリンク", chineseName: "飲料", reading: nil, price: nil, sectionName: "ドリンク", confidence: nil),
            MenuAnalysis.ItemDraft(japaneseName: "生ビール", chineseName: "生啤酒", reading: nil, price: 650, sectionName: "ドリンク", confidence: nil),
        ]
        let cleaned = AppleIntelligenceAIService.cleanUp(items, lines: lines)
        #expect(cleaned.map(\.japaneseName) == ["若どり唐揚げ", "とんかつ", "生ビール"])
        #expect(cleaned[0].options.isEmpty)
        #expect(cleaned[1].options.map(\.japaneseName) == ["大盛り"])
    }

    @Test("翻譯菜名、整理菜單、回答長輩的問題")
    @MainActor
    func realModel() async throws {
        guard AppleIntelligence.availability.isAvailable else {
            print("APPLE-AI: 不可用：\(AppleIntelligence.availability.reason ?? "")")
            return
        }
        guard #available(iOS 26, *) else { return }
        let service = AppleIntelligenceAIService()

        let translation = try await service.translate("若どり唐揚げ", to: .traditionalChinese)
        print("APPLE-AI 翻譯: \(translation.translated) / \(translation.reading ?? "-")")
        #expect(!translation.translated.isEmpty)

        let lines = ["揚げ物", "若どり唐揚げ ¥540", "手羽先 430円", "とんかつ 540円 大盛り +150円 定食セット +300円", "ドリンク", "生ビール ¥650", "※価格は税込です"]
        let analysis = try await service.analyzeMenu(textBlocks: lines.map { RecognizedTextBlock(text: $0, confidence: 1, boundingBox: .zero) }, image: nil)
        for item in analysis.items {
            print("APPLE-AI 菜單: \(item.japaneseName) | \(item.chineseName ?? "-") | \(item.reading ?? "-") | \(item.price.map { "\($0)" } ?? "-") | \(item.sectionName ?? "-")/\(item.sectionChinese ?? "-") | 選項 \(item.options.map { "\($0.groupName):\($0.japaneseName)\($0.priceDelta)" })")
        }
        #expect(analysis.items.count >= 3)
        #expect(analysis.items.contains { $0.japaneseName.contains("唐揚") })
        #expect(!analysis.items.contains { $0.japaneseName == "ドリンク" })
        if let tonkatsu = analysis.items.first(where: { $0.japaneseName == "とんかつ" }) {
            #expect(tonkatsu.options.contains { $0.japaneseName == "大盛り" }, "選項應該掛在とんかつ")
        }

        let chat = AssistantChat()
        await chat.send("日本便利商店的便當可以請店員加熱嗎？")
        let answer = chat.messages.last?.text ?? ""
        print("APPLE-AI 回答: \(answer)")
        #expect(chat.messages.count == 2)
        #expect(!answer.isEmpty && chat.messages.last?.isError == false)
    }
}
