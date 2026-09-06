import Foundation

/// 一份菜單。`roomId == nil` 代表還在本機草稿階段（尚未建立房間）。
struct Menu: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var roomId: UUID?
    var restaurantName: String?
    var createdAt: Date

    init(id: UUID = UUID(), roomId: UUID? = nil, restaurantName: String? = nil, createdAt: Date = .now) {
        self.id = id
        self.roomId = roomId
        self.restaurantName = restaurantName
        self.createdAt = createdAt
    }
}

struct MenuSection: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var menuId: UUID
    var nameJapanese: String
    var nameChinese: String?
    var sortOrder: Int

    init(id: UUID = UUID(), menuId: UUID, nameJapanese: String, nameChinese: String? = nil, sortOrder: Int = 0) {
        self.id = id
        self.menuId = menuId
        self.nameJapanese = nameJapanese
        self.nameChinese = nameChinese
        self.sortOrder = sortOrder
    }
}

/// 菜單上的一個品項。核心是結構化文字，圖片只是來源。
struct MenuItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var menuId: UUID
    var sectionId: UUID?
    var japaneseName: String
    var chineseName: String?
    var reading: String?
    var description: String?
    var price: Decimal?
    var currency: String
    var isRecommended: Bool
    var sortOrder: Int
    /// OCR / AI 的信心值（0–1），人工輸入為 nil
    var sourceConfidence: Double?
    /// 原始圖片在 Storage 的路徑（未來用）
    var sourceImagePath: String?

    init(
        id: UUID = UUID(),
        menuId: UUID,
        sectionId: UUID? = nil,
        japaneseName: String,
        chineseName: String? = nil,
        reading: String? = nil,
        description: String? = nil,
        price: Decimal? = nil,
        currency: String = "JPY",
        isRecommended: Bool = false,
        sortOrder: Int = 0,
        sourceConfidence: Double? = nil,
        sourceImagePath: String? = nil
    ) {
        self.id = id
        self.menuId = menuId
        self.sectionId = sectionId
        self.japaneseName = japaneseName
        self.chineseName = chineseName
        self.reading = reading
        self.description = description
        self.price = price
        self.currency = currency
        self.isRecommended = isRecommended
        self.sortOrder = sortOrder
        self.sourceConfidence = sourceConfidence
        self.sourceImagePath = sourceImagePath
    }

    /// 給長輩看的主要名稱：有中文用中文，否則用日文。
    var displayName: String { chineseName?.nilIfBlank ?? japaneseName }
}

/// 一份菜單連同它的分類與品項（Repository 讀取時的組合）。
struct MenuBundle: Hashable, Sendable {
    var menu: Menu
    var sections: [MenuSection]
    var items: [MenuItem]
    var options: [MenuItemOption] = []

    func options(for itemId: UUID) -> [MenuItemOption] {
        options.filter { $0.menuItemId == itemId }.sorted { $0.sortOrder < $1.sortOrder }
    }
}
