import Foundation
import UIKit

/// 「一張菜單照片 → 菜 + 價格」的完整流程。View 與 ViewModel 只認識這個 protocol。
protocol MenuRecognitionService: Sendable {
    func recognizeMenu(from image: UIImage) async throws -> MenuParseResult
}

/// 正式流程：Live Text（支援直排）→ 閱讀順序配對；
/// 配不出菜（或價格行明顯比配到的菜多）時再跑 Vision + 座標版面分析，取菜比較多的那份。
struct LiveMenuRecognitionService: MenuRecognitionService {
    private let liveText = LiveTextOCRService()
    private let vision = VisionOCRService()

    func recognizeMenu(from image: UIImage) async throws -> MenuParseResult {
        var liveTextResult: MenuParseResult?
        if let lines = try? await liveText.recognizeText(from: image), lines.contains(where: { !$0.text.isEmpty }) {
            let result = MenuTranscriptParser.parse(lines: lines.map(\.text))
            if !result.items.isEmpty || !result.otherLines.isEmpty {
                if !Self.shouldFallBackToVision(result) { return result }
                liveTextResult = result
            }
        }
        do {
            let blocks = try await vision.recognizeText(from: image)
            let visionResult = MenuLayoutAnalyzer.analyze(blocks)
            return Self.preferred(liveText: liveTextResult, vision: visionResult)
        } catch {
            // Vision 失敗但 Live Text 有結果：用 Live Text 的
            if let liveTextResult { return liveTextResult }
            throw error
        }
    }

    /// Live Text 讀到字但配不出菜、或「其他文字」裡像價格的行比配到的菜還多（欄式閱讀順序）→ 值得再用 Vision 試一次。
    static func shouldFallBackToVision(_ result: MenuParseResult) -> Bool {
        if result.items.isEmpty { return true }
        let priceLikeLines = result.otherLines.filter { PriceParser.priceOnly($0.name) != nil }.count
        return priceLikeLines > result.items.count
    }

    /// 兩份結果取菜比較多的；一樣多時以 Live Text 為準（直排、閱讀順序比較可靠）。
    static func preferred(liveText: MenuParseResult?, vision: MenuParseResult) -> MenuParseResult {
        guard let liveText else { return vision }
        return vision.items.count > liveText.items.count ? vision : liveText
    }
}

/// Preview / 測試用。
struct MockMenuRecognitionService: MenuRecognitionService {
    func recognizeMenu(from image: UIImage) async throws -> MenuParseResult {
        try await Task.sleep(for: .milliseconds(300))
        return MenuTranscriptParser.parse(lines: ["味噌串カツ定食", "八四〇円", "エビカツ定食", "九七〇円", "揚げ物", "若どり唐揚げ", "¥540"])
    }
}
