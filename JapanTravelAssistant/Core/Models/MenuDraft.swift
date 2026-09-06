import Foundation

/// 掃描後、還在編輯中的菜單。全部是使用者可以改的純文字，儲存在本機。
struct MenuDraft: Codable, Hashable, Sendable {
    var id: UUID
    var restaurantName: String
    var items: [MenuItemDraft]
    /// OCR 有讀到、但沒有配到價格的文字（店名、分類、說明…）。使用者可以挑出其中是菜的加入。
    var otherLines: [MenuItemDraft]
    /// 分類的中文名稱（日文分類 → 中文）
    var sectionChineseNames: [String: String]
    var createdAt: Date

    init(id: UUID = UUID(), restaurantName: String = "", items: [MenuItemDraft] = [], otherLines: [MenuItemDraft] = [], sectionChineseNames: [String: String] = [:], createdAt: Date = .now) {
        self.id = id
        self.restaurantName = restaurantName
        self.items = items
        self.otherLines = otherLines
        self.sectionChineseNames = sectionChineseNames
        self.createdAt = createdAt
    }

    // 舊版草稿缺欄位也要能讀
    private enum CodingKeys: String, CodingKey { case id, restaurantName, items, otherLines, sectionChineseNames, createdAt }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        restaurantName = try container.decodeIfPresent(String.self, forKey: .restaurantName) ?? ""
        items = try container.decodeIfPresent([MenuItemDraft].self, forKey: .items) ?? []
        otherLines = try container.decodeIfPresent([MenuItemDraft].self, forKey: .otherLines) ?? []
        sectionChineseNames = try container.decodeIfPresent([String: String].self, forKey: .sectionChineseNames) ?? [:]
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
    }

    /// 分類名稱，依第一次出現的順序
    var sectionNames: [String] {
        var seen = Set<String>()
        return items.compactMap { item in
            guard let name = item.sectionName?.nilIfBlank, !seen.contains(name) else { return nil }
            seen.insert(name)
            return name
        }
    }

    struct Group: Identifiable, Hashable {
        var section: String?          // nil = 沒有分類
        var sectionChinese: String?
        var items: [MenuItemDraft]
        var id: String { section ?? "__none__" }
    }

    /// 依分類分組（順序照第一次出現）；沒有分類的放最後。
    var groupedItems: [Group] {
        var groups: [Group] = sectionNames.map { name in
            Group(section: name, sectionChinese: sectionChineseNames[name]?.nilIfBlank, items: items.filter { $0.sectionName?.nilIfBlank == name })
        }
        let unsectioned = items.filter { $0.sectionName?.nilIfBlank == nil }
        if !unsectioned.isEmpty {
            groups.append(Group(section: nil, sectionChinese: nil, items: unsectioned))
        }
        return groups
    }

    /// 轉成正式的結構化菜單（建立房間時使用）。
    /// 每次都產生全新的 ID：同一份草稿可以建立好幾個房間，不會撞到資料庫裡已經存在的 ID。
    func toBundle() -> MenuBundle {
        let menu = Menu(id: UUID(), roomId: nil, restaurantName: restaurantName.nilIfBlank, createdAt: createdAt)
        var itemIds: [UUID: UUID] = [:]
        for draft in items { itemIds[draft.id] = UUID() }

        // 依出現順序建立分類
        var sections: [MenuSection] = []
        var sectionIds: [String: UUID] = [:]
        for draft in items {
            guard let name = draft.sectionName?.nilIfBlank, sectionIds[name] == nil else { continue }
            let section = MenuSection(menuId: menu.id, nameJapanese: name, nameChinese: sectionChineseNames[name]?.nilIfBlank, sortOrder: sections.count)
            sections.append(section)
            sectionIds[name] = section.id
        }

        var options: [MenuItemOption] = []
        for draft in items {
            for (index, option) in draft.options.filter(\.isValid).enumerated() {
                options.append(MenuItemOption(
                    id: UUID(),
                    menuItemId: itemIds[draft.id] ?? draft.id,
                    groupName: option.groupName.trimmingCharacters(in: .whitespaces),
                    nameJapanese: option.japaneseName.trimmingCharacters(in: .whitespaces),
                    nameChinese: option.chineseName.nilIfBlank,
                    priceDelta: option.priceDelta,
                    sortOrder: index
                ))
            }
        }

        let menuItems = items.enumerated().map { index, draft in
            MenuItem(
                id: itemIds[draft.id] ?? draft.id,
                menuId: menu.id,
                sectionId: draft.sectionName?.nilIfBlank.flatMap { sectionIds[$0] },
                japaneseName: draft.japaneseName.trimmingCharacters(in: .whitespacesAndNewlines),
                chineseName: draft.chineseName.nilIfBlank,
                reading: draft.reading?.nilIfBlank,
                description: draft.note?.nilIfBlank,
                price: draft.price,
                currency: "JPY",
                sortOrder: index,
                sourceConfidence: draft.sourceConfidence
            )
        }
        return MenuBundle(menu: menu, sections: sections, items: menuItems, options: options)
    }
}

/// 草稿階段的選項（純文字，可編輯）
struct MenuOptionDraft: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var groupName: String
    var japaneseName: String
    var chineseName: String
    /// 價差文字，例如 +150、-100、0
    var priceDeltaText: String

    init(id: UUID = UUID(), groupName: String, japaneseName: String, chineseName: String = "", priceDeltaText: String = "0") {
        self.id = id
        self.groupName = groupName
        self.japaneseName = japaneseName
        self.chineseName = chineseName
        self.priceDeltaText = priceDeltaText
    }

    var priceDelta: Decimal { PriceFormatter.parseDelta(priceDeltaText) ?? 0 }
    var isValid: Bool { groupName.nilIfBlank != nil && japaneseName.nilIfBlank != nil }

    var displayText: String {
        let name = chineseName.nilIfBlank ?? japaneseName
        let delta = priceDelta
        if delta == 0 { return name }
        let absolute = PriceFormatter.string(abs(delta)) ?? "\(abs(delta))"
        return "\(name) \(delta > 0 ? "+" : "−")\(absolute)"
    }
}

struct MenuItemDraft: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var japaneseName: String
    var chineseName: String
    var priceText: String
    var sourceConfidence: Double?
    /// OCR 的原始那一行，方便使用者對照
    var ocrText: String?
    /// 分類（例如 揚げ物），來自 ChatGPT 匯入或之後的手動設定
    var sectionName: String?
    /// 一句說明（食材、口味）
    var note: String?
    /// 選項（份量、套餐升級…），同群組單選
    var options: [MenuOptionDraft]
    /// 羅馬拼音（例如 tonkatsu）。ChatGPT 給的優先，否則由 iOS 斷詞器產生。
    var reading: String?

    init(id: UUID = UUID(), japaneseName: String, chineseName: String = "", priceText: String = "", sourceConfidence: Double? = nil, ocrText: String? = nil, sectionName: String? = nil, note: String? = nil, options: [MenuOptionDraft] = [], reading: String? = nil) {
        self.id = id
        self.japaneseName = japaneseName
        self.chineseName = chineseName
        self.priceText = priceText
        self.sourceConfidence = sourceConfidence
        self.ocrText = ocrText
        self.sectionName = sectionName
        self.note = note
        self.options = options
        self.reading = reading
    }

    // 舊草稿缺欄位也要能讀
    private enum CodingKeys: String, CodingKey { case id, japaneseName, chineseName, priceText, sourceConfidence, ocrText, sectionName, note, options, reading }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        japaneseName = try c.decodeIfPresent(String.self, forKey: .japaneseName) ?? ""
        chineseName = try c.decodeIfPresent(String.self, forKey: .chineseName) ?? ""
        priceText = try c.decodeIfPresent(String.self, forKey: .priceText) ?? ""
        sourceConfidence = try c.decodeIfPresent(Double.self, forKey: .sourceConfidence)
        ocrText = try c.decodeIfPresent(String.self, forKey: .ocrText)
        sectionName = try c.decodeIfPresent(String.self, forKey: .sectionName)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        options = try c.decodeIfPresent([MenuOptionDraft].self, forKey: .options) ?? []
        reading = try c.decodeIfPresent(String.self, forKey: .reading)
    }

    /// 選項摘要，例如「大份 +¥150、定食 +¥300」
    var optionsSummary: String? {
        let valid = options.filter(\.isValid)
        guard !valid.isEmpty else { return nil }
        return valid.map(\.displayText).joined(separator: "、")
    }

    /// 比對用：去空白、全形轉半形
    var normalizedJapaneseName: String {
        PriceParser.normalize(japaneseName).replacingOccurrences(of: " ", with: "")
    }

    var price: Decimal? { PriceFormatter.parse(priceText) }
    var isValid: Bool { japaneseName.nilIfBlank != nil }

    /// 從版面分析的結果建立草稿。
    static func from(candidate: MenuCandidate) -> MenuItemDraft {
        MenuItemDraft(
            japaneseName: candidate.name,
            priceText: candidate.price.map { "\($0)" } ?? "",
            sourceConfidence: candidate.confidence,
            ocrText: candidate.sourceText,
            sectionName: candidate.section
        )
    }
}
