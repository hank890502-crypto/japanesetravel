import Foundation

/// 一道菜的一個選項，例如「份量：大盛り +150」「套餐：定食セット +300」。
/// 同一個 group 內單選；priceDelta 相對於菜的基本價格，可正可負可為 0。
struct MenuItemOption: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var menuItemId: UUID
    /// 群組名稱（給家人看的中文，例如 份量、套餐）
    var groupName: String
    var nameJapanese: String
    var nameChinese: String?
    var priceDelta: Decimal
    var sortOrder: Int

    init(id: UUID = UUID(), menuItemId: UUID, groupName: String, nameJapanese: String, nameChinese: String? = nil, priceDelta: Decimal = 0, sortOrder: Int = 0) {
        self.id = id
        self.menuItemId = menuItemId
        self.groupName = groupName
        self.nameJapanese = nameJapanese
        self.nameChinese = nameChinese
        self.priceDelta = priceDelta
        self.sortOrder = sortOrder
    }

    var displayName: String { nameChinese?.nilIfBlank ?? nameJapanese }

    /// +¥150、−¥100、±0
    var priceDeltaText: String {
        if priceDelta == 0 { return "±0" }
        let absolute = PriceFormatter.string(abs(priceDelta)) ?? "\(abs(priceDelta))"
        return priceDelta > 0 ? "+\(absolute)" : "−\(absolute)"
    }
}

extension Array where Element == MenuItemOption {
    /// 依群組分組，保留出現順序。
    var groupedByName: [(group: String, options: [MenuItemOption])] {
        var order: [String] = []
        var map: [String: [MenuItemOption]] = [:]
        for option in self.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            if map[option.groupName] == nil { order.append(option.groupName) }
            map[option.groupName, default: []].append(option)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    /// 選項組合的識別字串（排序後的 id），用來區分「同一道菜的不同組合」。規則見 `MenuSelection.variantKey(for:)`。
    var variantKey: String {
        MenuSelection.variantKey(for: map(\.id))
    }
}
