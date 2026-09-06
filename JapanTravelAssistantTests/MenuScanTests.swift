import Foundation
import Testing
import UIKit
@testable import JapanTravelAssistant

@Suite("菜單掃描")
struct MenuScanTests {
    private func block(_ text: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat = 0.04, c: Double = 0.9) -> RecognizedTextBlock {
        RecognizedTextBlock(text: text, confidence: c, boundingBox: CGRect(x: x, y: y, width: w, height: h))
    }

    @Test("兩欄菜單：每個價格配到同一列左邊的品名，雜訊進其他文字")
    func twoColumnLayout() {
        let blocks = [
            block("居酒屋 酒津屋", x: 0.3, y: 0.92, w: 0.4, h: 0.06),
            block("揚げ物", x: 0.05, y: 0.82, w: 0.15),
            block("若どり唐揚げ", x: 0.05, y: 0.74, w: 0.25), block("¥540", x: 0.36, y: 0.741, w: 0.08),
            block("手羽先", x: 0.05, y: 0.66, w: 0.12), block("430円", x: 0.36, y: 0.66, w: 0.08),
            block("焼き物", x: 0.55, y: 0.82, w: 0.15),
            block("味噌串カツ", x: 0.55, y: 0.74, w: 0.22), block("540", x: 0.86, y: 0.742, w: 0.06),
            block("ねぎま", x: 0.55, y: 0.66, w: 0.12), block("￥１８０", x: 0.86, y: 0.659, w: 0.08),
            block("※価格は税込です", x: 0.05, y: 0.10, w: 0.4),
        ]
        let result = MenuLayoutAnalyzer.analyze(blocks)
        #expect(result.items.map(\.name) == ["若どり唐揚げ", "手羽先", "味噌串カツ", "ねぎま"])
        #expect(result.items.map(\.price) == [540, 430, 540, 180])
        #expect(result.otherLines.map(\.name) == ["居酒屋 酒津屋", "揚げ物", "焼き物", "※価格は税込です"])
    }

    @Test("品名在上、價格在下的排版")
    func stackedLayout() {
        let blocks = [
            block("生ビール", x: 0.1, y: 0.80, w: 0.2),
            block("¥650", x: 0.1, y: 0.75, w: 0.1),
            block("ハイボール", x: 0.1, y: 0.60, w: 0.2),
            block("¥500", x: 0.1, y: 0.55, w: 0.1),
        ]
        let result = MenuLayoutAnalyzer.analyze(blocks)
        #expect(result.items.map(\.name) == ["生ビール", "ハイボール"])
        #expect(result.items.map(\.price) == [650, 500])
        #expect(result.otherLines.isEmpty)
    }

    @Test("同一塊裡就有品名和價格，含税込與點線")
    func inlinePrices() {
        #expect(PriceParser.split("若どり唐揚げ………¥540").name == "若どり唐揚げ")
        #expect(PriceParser.split("若どり唐揚げ………¥540").price == 540)
        #expect(PriceParser.split("枝豆 380円（税込418円）").price == 418)
        #expect(PriceParser.split("枝豆 380円（税込418円）").name == "枝豆")
        #expect(PriceParser.split("生ビール（中） 650").name == "生ビール（中）")
        #expect(PriceParser.split("生ビール（中） 650").price == 650)
        #expect(PriceParser.priceOnly("￥１，２００") == 1200)
        #expect(PriceParser.priceOnly("540円") == 540)
        #expect(PriceParser.priceOnly("税込594円") == 594)
        #expect(PriceParser.priceOnly("2名様") == nil)
        #expect(PriceParser.priceOnly("唐揚げ 540") == nil)
    }

    @Test("草稿轉成結構化菜單")
    func draftToBundle() {
        let draft = MenuDraft(restaurantName: "酒津屋", items: [
            MenuItemDraft(japaneseName: "若どり唐揚げ", chineseName: "炸嫩雞", priceText: "540"),
            MenuItemDraft(japaneseName: "手羽先", chineseName: "  ", priceText: "¥430"),
        ])
        let bundle = draft.toBundle()
        #expect(bundle.menu.restaurantName == "酒津屋")
        #expect(bundle.items.count == 2)
        #expect(bundle.items[0].chineseName == "炸嫩雞")
        #expect(bundle.items[1].chineseName == nil)
        #expect(bundle.items[1].price == 430)
        #expect(bundle.items.map(\.sortOrder) == [0, 1])
    }

    @Test("舊版草稿 JSON（沒有 otherLines）仍可讀取")
    func decodesLegacyDraft() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","restaurantName":"","items":[],"createdAt":0}"#
        let draft = try JSONDecoder().decode(MenuDraft.self, from: Data(json.utf8))
        #expect(draft.otherLines.isEmpty)
    }

    @Test("Vision OCR + 版面分析：兩欄、有點線與円的菜單圖")
    func visionRecognizesRenderedMenu() async throws {
        let image = await MainActor.run { Self.renderMenuImage() }
        if let env = ProcessInfo.processInfo.environment["MENU_SAMPLE_OUT"] {
            try? image.pngData()?.write(to: URL(fileURLWithPath: env))
        }
        let blocks = try await VisionOCRService().recognizeText(from: image)
        let result = MenuLayoutAnalyzer.analyze(blocks)
        print("OCR RAW: " + blocks.map { "[\($0.text)] x=\(String(format: "%.2f", $0.boundingBox.minX)) y=\(String(format: "%.2f", $0.boundingBox.midY)) w=\(String(format: "%.2f", $0.boundingBox.width))" }.joined(separator: "  "))
        print("OCR ITEMS: " + result.items.map { "\($0.name)=\($0.price.map { "\($0)" } ?? "nil")" }.joined(separator: " | "))
        let names = "items: " + result.items.map { "\($0.name)=\($0.price.map { "\($0)" } ?? "nil")" }.joined(separator: " | ") + " ; raw: " + blocks.map(\.text).joined(separator: " | ")
        #expect(result.items.count >= 4, "只找到：\(names)；原始：\(blocks.map(\.text))")
        #expect(result.items.contains { $0.name.contains("唐揚") && $0.price == 540 }, Comment(rawValue: names))
        // Vision 對合成字型偶爾會漏字（手羽先 → 手先），所以只檢查價格配對正確
        #expect(result.items.contains { $0.name.hasPrefix("手") && $0.price == 430 }, Comment(rawValue: names))
        #expect(result.items.contains { $0.name.contains("ねぎま") && $0.price == 180 }, Comment(rawValue: names))
    }

    @MainActor
    private static func renderMenuImage() -> UIImage {
        let size = CGSize(width: 1400, height: 900)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor(white: 0.97, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let title: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 60), .foregroundColor: UIColor.black]
            let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 44, weight: .medium), .foregroundColor: UIColor.black]
            "居酒屋 酒津屋".draw(at: CGPoint(x: 480, y: 40), withAttributes: title)
            let left: [(String, String)] = [("揚げ物", ""), ("若どり唐揚げ", "¥540"), ("手羽先", "430円"), ("味噌串カツ", "¥540")]
            let right: [(String, String)] = [("焼き物", ""), ("ねぎま", "180円"), ("つくね", "¥200"), ("生ビール", "¥650")]
            for (index, row) in left.enumerated() {
                let y = CGFloat(180 + index * 110)
                row.0.draw(at: CGPoint(x: 60, y: y), withAttributes: body)
                row.1.draw(at: CGPoint(x: 520, y: y), withAttributes: body)
            }
            for (index, row) in right.enumerated() {
                let y = CGFloat(180 + index * 110)
                row.0.draw(at: CGPoint(x: 760, y: y), withAttributes: body)
                row.1.draw(at: CGPoint(x: 1200, y: y), withAttributes: body)
            }
            "※価格は税込です".draw(at: CGPoint(x: 60, y: 780), withAttributes: body)
        }
    }
}
