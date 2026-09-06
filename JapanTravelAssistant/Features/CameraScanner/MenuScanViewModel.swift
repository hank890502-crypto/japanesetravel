import Foundation
import Observation
import UIKit

/// 拍菜單 → OCR → 產生草稿。不碰 UI，只回報狀態。
@Observable
@MainActor
final class MenuScanViewModel {
    enum Phase: Equatable {
        case idle
        case recognizing
        case failed(UserFacingError)
    }

    private(set) var phase: Phase = .idle
    private(set) var previewImage: UIImage?

    private let recognizer: any MenuRecognitionService

    init(recognizer: any MenuRecognitionService) {
        self.recognizer = recognizer
    }

    /// 回傳 true 代表成功並已寫入草稿。可一次處理多頁（文件掃描）。
    func process(images: [UIImage], into store: MenuDraftStore) async -> Bool {
        guard let first = images.first else { return false }
        previewImage = first.downscaled(maxDimension: 1200)
        phase = .recognizing

        var items: [MenuItemDraft] = []
        var otherLines: [MenuItemDraft] = []
        var anyText = false
        for image in images {
            // OCR 用接近原圖的解析度：縮太小，密集的小字就讀不到。
            let working = image.downscaled(maxDimension: 4000)
            do {
                let result = try await recognizer.recognizeMenu(from: working)
                anyText = anyText || !result.items.isEmpty || !result.otherLines.isEmpty
                items += result.items.map(MenuItemDraft.from(candidate:)).filter(\.isValid)
                otherLines += result.otherLines.map(MenuItemDraft.from(candidate:)).filter(\.isValid)
            } catch {
                phase = .failed(UserFacingError(title: "辨識失敗", message: "請再拍一次，或改用手動輸入。"))
                return false
            }
        }

        guard anyText else {
            phase = .failed(UserFacingError(
                title: "沒有找到文字",
                message: "請靠近一點、光線亮一點再拍一次，或改用手動輸入。"
            ))
            return false
        }

        store.startNew(items: items, otherLines: otherLines, images: images.map { $0.downscaled(maxDimension: 2000) })
        phase = .idle
        return true
    }

    func process(image: UIImage, into store: MenuDraftStore) async -> Bool {
        await process(images: [image], into: store)
    }

    func reset() {
        phase = .idle
        previewImage = nil
    }
}
