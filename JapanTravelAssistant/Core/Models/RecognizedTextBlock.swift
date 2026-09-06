import CoreGraphics
import Foundation

/// OCR 辨識出的一段文字。boundingBox 為 Vision 座標（左下原點、0–1 正規化）。
struct RecognizedTextBlock: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var text: String
    var confidence: Double
    var boundingBox: CGRect
}
