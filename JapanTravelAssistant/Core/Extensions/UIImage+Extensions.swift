import ImageIO
import UIKit
import UniformTypeIdentifiers

extension UIImage {
    /// 縮小到最長邊不超過 maxDimension，避免相簿原圖太大佔記憶體。
    /// UIGraphicsImageRenderer 在背景執行緒也能用；要處理大圖請放到 Task.detached 裡呼叫。
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// 直接從照片檔的資料（JPEG／HEIC／PNG）產生縮圖，最長邊不超過 maxPixelSize。
    /// 用 ImageIO 降採樣：不需要先把整張 48MP 原圖解碼出來，記憶體只有縮圖大小；
    /// 方向（EXIF）也一併轉正。讀不到就回傳 nil。
    static func downsampled(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize),
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }
}

/// UIImage 本身是不可變的、可以跨執行緒使用，但沒有標 Sendable；縮圖與 OCR 要在背景做時用這個包起來傳。
struct TransferableImage: @unchecked Sendable {
    let image: UIImage
}
