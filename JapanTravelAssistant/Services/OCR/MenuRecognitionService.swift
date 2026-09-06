import Foundation
import UIKit

/// 「一張菜單照片 → 菜 + 價格」的完整流程。View 與 ViewModel 只認識這個 protocol。
protocol MenuRecognitionService: Sendable {
    func recognizeMenu(from image: UIImage) async throws -> MenuParseResult
}

/// 正式流程：Live Text（支援直排）→ 閱讀順序配對；失敗時退回 Vision + 座標版面分析。
struct LiveMenuRecognitionService: MenuRecognitionService {
    private let liveText = LiveTextOCRService()
    private let vision = VisionOCRService()

    func recognizeMenu(from image: UIImage) async throws -> MenuParseResult {
        if let lines = try? await liveText.recognizeText(from: image), lines.contains(where: { !$0.text.isEmpty }) {
            let result = MenuTranscriptParser.parse(lines: lines.map(\.text))
            if !result.items.isEmpty || !result.otherLines.isEmpty {
                return result
            }
        }
        let blocks = try await vision.recognizeText(from: image)
        return MenuLayoutAnalyzer.analyze(blocks)
    }
}

/// Preview / 測試用。
struct MockMenuRecognitionService: MenuRecognitionService {
    func recognizeMenu(from image: UIImage) async throws -> MenuParseResult {
        try await Task.sleep(for: .milliseconds(300))
        return MenuTranscriptParser.parse(lines: ["味噌串カツ定食", "八四〇円", "エビカツ定食", "九七〇円", "揚げ物", "若どり唐揚げ", "¥540"])
    }
}
