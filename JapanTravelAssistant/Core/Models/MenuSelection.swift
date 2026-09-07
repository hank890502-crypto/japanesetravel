import Foundation

/// 「某位成員」對「某個品項」的數量。
/// 每人各自一列，不共用一個總數，避免多人同時修改互相覆蓋。
struct MenuSelection: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var roomId: UUID
    var memberId: UUID
    var menuItemId: UUID
    /// 選的選項（每個群組最多一個）。沒有選項就是空陣列。
    var optionIds: [UUID]
    var quantity: Int
    var note: String?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        roomId: UUID,
        memberId: UUID,
        menuItemId: UUID,
        optionIds: [UUID] = [],
        quantity: Int,
        note: String? = nil,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.roomId = roomId
        self.memberId = memberId
        self.menuItemId = menuItemId
        self.optionIds = optionIds
        self.quantity = quantity
        self.note = note
        self.updatedAt = updatedAt
    }

    /// 同一道菜、同一組選項 = 同一種東西
    var variantKey: String { Self.variantKey(for: optionIds) }

    /// 選項組合的識別字串。App、網頁版與資料庫三邊都用同一條規則：
    /// **小寫 UUID、排序後用「,」連接**；沒有選項是空字串。
    /// （資料庫的 BEFORE INSERT/UPDATE trigger 也用同樣規則重算，所以任一端算錯也不會拆成兩行。）
    static func variantKey(for optionIds: [UUID]) -> String {
        optionIds.map { $0.uuidString.lowercased() }.sorted().joined(separator: ",")
    }
}

/// Host 彙總畫面的一行：某個品項的總數，以及每個人各點了幾份。
struct OrderSummaryLine: Identifiable, Hashable, Sendable {
    struct MemberQuantity: Hashable, Sendable {
        var member: RoomMember
        var quantity: Int
    }

    var menuItem: MenuItem
    /// 這一行代表的選項組合（可能為空）
    var options: [MenuItemOption]
    var totalQuantity: Int
    var byMember: [MemberQuantity]

    var id: String { "\(menuItem.id.uuidString)#\(options.variantKey)" }

    /// 單價 = 基本價 + 選項價差（基本價不明時為 nil）
    var unitPrice: Decimal? {
        guard let base = menuItem.price else { return nil }
        return base + options.reduce(Decimal(0)) { $0 + $1.priceDelta }
    }

    var subtotal: Decimal? { unitPrice.map { $0 * Decimal(totalQuantity) } }

    /// 給店員看的名稱：菜名 + 選項日文
    var staffDisplayName: String {
        let suffix = options.map(\.nameJapanese).joined(separator: "・")
        return suffix.isEmpty ? menuItem.japaneseName : "\(menuItem.japaneseName)（\(suffix)）"
    }
}

/// 純函式：把品項、成員、選擇組合成彙總。不依賴任何 Service，方便測試。
enum OrderSummaryBuilder {
    static func build(items: [MenuItem], options: [MenuItemOption] = [], members: [RoomMember], selections: [MenuSelection]) -> [OrderSummaryLine] {
        let membersById = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
        let optionsById = Dictionary(uniqueKeysWithValues: options.map { ($0.id, $0) })
        let active = selections.filter { $0.quantity > 0 }
        let selectionsByItem = Dictionary(grouping: active, by: \.menuItemId)

        return items
            .sorted { ($0.sortOrder, $0.japaneseName) < ($1.sortOrder, $1.japaneseName) }
            .flatMap { item -> [OrderSummaryLine] in
                guard let itemSelections = selectionsByItem[item.id] else { return [] }
                // 同一道菜依「選項組合」分成不同行
                let byVariant = Dictionary(grouping: itemSelections, by: \.variantKey)
                return byVariant.keys.sorted().compactMap { key -> OrderSummaryLine? in
                    let variantSelections = byVariant[key] ?? []
                    let byMember = variantSelections
                        .compactMap { selection -> OrderSummaryLine.MemberQuantity? in
                            guard let member = membersById[selection.memberId] else { return nil }
                            return .init(member: member, quantity: selection.quantity)
                        }
                        .sorted { $0.member.createdAt < $1.member.createdAt }
                    let total = byMember.reduce(0) { $0 + $1.quantity }
                    guard total > 0 else { return nil }
                    let variantOptions = (variantSelections.first?.optionIds ?? [])
                        .compactMap { optionsById[$0] }
                        .sorted { $0.sortOrder < $1.sortOrder }
                    return OrderSummaryLine(menuItem: item, options: variantOptions, totalQuantity: total, byMember: byMember)
                }
            }
    }

    static func totalQuantity(of lines: [OrderSummaryLine]) -> Int {
        lines.reduce(0) { $0 + $1.totalQuantity }
    }

    /// 總金額（有任何一行沒有價格就回傳 nil）
    static func totalPrice(of lines: [OrderSummaryLine]) -> Decimal? {
        var total = Decimal(0)
        for line in lines {
            guard let subtotal = line.subtotal else { return nil }
            total += subtotal
        }
        return total
    }
}
