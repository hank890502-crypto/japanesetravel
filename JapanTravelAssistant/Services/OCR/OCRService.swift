import Foundation
import UIKit

/// 本機文字辨識。M2 加入 VisionOCRService（Apple Vision，日文）。
protocol OCRService: Sendable {
    func recognizeText(from image: UIImage) async throws -> [RecognizedTextBlock]
}

/// 假的 OCR：回傳固定的三行菜單，供 Preview 與尚未實作前使用。
struct MockOCRService: OCRService {
    var delay: Duration = .milliseconds(300)

    func recognizeText(from image: UIImage) async throws -> [RecognizedTextBlock] {
        try await Task.sleep(for: delay)
        return [
            RecognizedTextBlock(text: "若どり唐揚げ ¥540", confidence: 0.95, boundingBox: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.06)),
            RecognizedTextBlock(text: "手羽先 ¥430", confidence: 0.92, boundingBox: CGRect(x: 0.1, y: 0.6, width: 0.8, height: 0.06)),
            RecognizedTextBlock(text: "味噌串カツ ¥540", confidence: 0.90, boundingBox: CGRect(x: 0.1, y: 0.5, width: 0.8, height: 0.06)),
        ]
    }
}
