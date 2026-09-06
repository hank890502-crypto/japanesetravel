import Foundation
import ImageIO
import UIKit
import Vision

/// Apple Vision 本機文字辨識，日文優先。完全離線，不需要任何 API。
struct VisionOCRService: OCRService {
    /// 語言校正：用字典把相近的字「修正」。菜名常不在字典裡，預設關閉；可在測試中比較。
    var usesLanguageCorrection: Bool = false
    var languages: [String] = ["ja-JP"]

    func recognizeText(from image: UIImage) async throws -> [RecognizedTextBlock] {
        guard let cgImage = image.cgImage else {
            throw UserFacingError(title: "無法讀取這張照片", message: "請換一張照片，或重新拍一次。")
        }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        // Vision 的 perform 是同步且耗時的，放到背景執行。
        return try await Task.detached(priority: .userInitiated) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[RecognizedTextBlock], Error>) in
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                    let blocks = observations.compactMap { observation -> RecognizedTextBlock? in
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return nil }
                        return RecognizedTextBlock(text: text, confidence: Double(candidate.confidence), boundingBox: observation.boundingBox)
                    }
                    continuation.resume(returning: blocks)
                }
                request.recognitionLevel = .accurate
                // 只指定日文：混入英文模型會把假名／漢字硬猜成英文字。
                request.recognitionLanguages = languages
                request.usesLanguageCorrection = usesLanguageCorrection
                request.automaticallyDetectsLanguage = false

                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }.value
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
