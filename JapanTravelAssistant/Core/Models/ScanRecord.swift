import Foundation

/// 一次掃描的紀錄：原始圖片位置與 OCR 原文。菜單本身是結構化資料，這裡只是來源。
struct ScanRecord: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var roomId: UUID?
    var menuId: UUID?
    var storagePath: String?
    var ocrText: String?
    var createdAt: Date

    init(id: UUID = UUID(), roomId: UUID? = nil, menuId: UUID? = nil, storagePath: String? = nil, ocrText: String? = nil, createdAt: Date = .now) {
        self.id = id
        self.roomId = roomId
        self.menuId = menuId
        self.storagePath = storagePath
        self.ocrText = ocrText
        self.createdAt = createdAt
    }
}
