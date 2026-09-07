import Foundation
import Observation
import UIKit

/// 拍菜單 → OCR → 產生辨識結果。不碰 UI、也不直接改草稿：
/// 要「換成新的菜單」還是「加到目前的菜單」由畫面問過使用者再決定。
@Observable
@MainActor
final class MenuScanViewModel {
    enum Phase: Equatable {
        case idle
        case recognizing
        case failed(UserFacingError)
    }

    /// 要辨識的來源：相簿選的照片檔（直接從檔案降採樣，不用先把整張原圖解碼出來）或相機／文件掃描給的圖。
    enum Source: Sendable {
        case data(Data)
        case image(TransferableImage)
    }

    /// 辨識完成、還沒寫進草稿的結果
    struct Recognized {
        var items: [MenuItemDraft]
        var otherLines: [MenuItemDraft]
        /// 縮小過、留給使用者對照的照片
        var images: [UIImage]
    }

    private(set) var phase: Phase = .idle
    private(set) var previewImage: UIImage?

    private let recognizer: any MenuRecognitionService

    /// OCR 用接近原圖的解析度：縮太小，密集的小字就讀不到。
    private static let ocrMaxPixelSize: CGFloat = 4000
    /// 留在草稿裡給使用者對照的照片
    private static let storedMaxPixelSize: CGFloat = 2000
    private static let previewMaxPixelSize: CGFloat = 1200

    init(recognizer: any MenuRecognitionService) {
        self.recognizer = recognizer
    }

    /// 辨識一張或多張（文件掃描可多頁）。成功回傳結果，失敗時 phase 會變成 .failed 並回傳 nil。
    func recognize(_ sources: [Source]) async -> Recognized? {
        guard !sources.isEmpty else { return nil }
        previewImage = nil
        phase = .recognizing
        // 讓畫面先切到「辨識中」，再開始縮圖與辨識
        await Task.yield()

        var items: [MenuItemDraft] = []
        var otherLines: [MenuItemDraft] = []
        var storedImages: [UIImage] = []
        var anyText = false
        for (index, source) in sources.enumerated() {
            // 一張一張處理：縮圖在背景做，同時只留一張工作圖在記憶體裡
            guard let working = await Self.downsample(source, maxPixelSize: Self.ocrMaxPixelSize)?.image else { continue }
            if index == 0 {
                previewImage = await Self.downsample(.image(TransferableImage(image: working)), maxPixelSize: Self.previewMaxPixelSize)?.image
            }
            do {
                let result = try await recognizer.recognizeMenu(from: working)
                anyText = anyText || !result.items.isEmpty || !result.otherLines.isEmpty
                items += result.items.map(MenuItemDraft.from(candidate:)).filter(\.isValid)
                otherLines += result.otherLines.map(MenuItemDraft.from(candidate:)).filter(\.isValid)
            } catch {
                phase = .failed(UserFacingError(title: "辨識失敗", message: "請再拍一次，或改用手動輸入。"))
                return nil
            }
            // 保存用的照片從 4000px 的工作圖再縮，不回頭解碼原圖
            if let stored = await Self.downsample(.image(TransferableImage(image: working)), maxPixelSize: Self.storedMaxPixelSize)?.image {
                storedImages.append(stored)
            }
        }

        guard anyText else {
            phase = .failed(UserFacingError(
                title: "沒有找到文字",
                message: "請靠近一點、光線亮一點再拍一次，或改用手動輸入。"
            ))
            return nil
        }

        phase = .idle
        return Recognized(items: items, otherLines: otherLines, images: storedImages)
    }

    func recognize(images: [UIImage]) async -> Recognized? {
        await recognize(images.map { .image(TransferableImage(image: $0)) })
    }

    func reset() {
        phase = .idle
        previewImage = nil
    }

    /// 在背景縮圖。相簿照片檔用 ImageIO 降採樣（不解碼整張原圖、EXIF 方向轉正）；已解碼的圖用 UIGraphicsImageRenderer。
    private nonisolated static func downsample(_ source: Source, maxPixelSize: CGFloat) async -> TransferableImage? {
        await Task.detached(priority: .userInitiated) { () -> TransferableImage? in
            switch source {
            case .data(let data):
                return UIImage.downsampled(data: data, maxPixelSize: maxPixelSize).map { TransferableImage(image: $0) }
            case .image(let wrapped):
                return TransferableImage(image: wrapped.image.downscaled(maxDimension: maxPixelSize))
            }
        }.value
    }
}
