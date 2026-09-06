import Foundation
import UIKit
import VisionKit

/// Apple Live Text 引擎（VisionKit ImageAnalyzer）。
/// 和 Vision 的差別：支援直排日文、輸出是「閱讀順序」的整行文字，但沒有座標。
/// iOS 17 能跑的機型全部支援。
struct LiveTextOCRService: OCRService {
    static var isSupported: Bool { ImageAnalyzer.isSupported }

    func recognizeText(from image: UIImage) async throws -> [RecognizedTextBlock] {
        guard Self.isSupported else {
            throw UserFacingError(title: "這台手機不支援文字辨識", message: "請改用手動輸入。", isRetryable: false)
        }
        let transcript = try await analyze(image)
        return transcript
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { RecognizedTextBlock(text: $0, confidence: 0.9, boundingBox: .zero) }
    }

    @MainActor
    private func analyze(_ image: UIImage) async throws -> String {
        let analyzer = ImageAnalyzer()
        let configuration = ImageAnalyzer.Configuration([.text])
        let analysis = try await analyzer.analyze(image, configuration: configuration)
        return analysis.transcript
    }
}
