import Foundation
import Observation

/// 一個房間裡的所有狀態：成員、菜單、每個人的點餐。
/// 三條即時串流各自更新；斷線後串流結束會自動重連（重新訂閱並整份重抓）。
///
/// 效能：分組、彙總、每道菜的選項、我的數量、拼音都在資料變動時算一次存起來，
/// 畫面重繪時只是查表，不會每一列都重新過濾整份資料。
@Observable
@MainActor
final class RoomViewModel {
    let session: RoomSession
    private(set) var members: [RoomMember] = [] { didSet { rebuildOrderCaches() } }
    private(set) var menus: [MenuBundle] = [] { didSet { rebuildMenuCaches(); rebuildOrderCaches() } }
    private(set) var selections: [MenuSelection] = [] { didSet { rebuildOrderCaches() } }
    private(set) var hasLoadedMenu = false
    var error: UserFacingError?

    // 由 menus 推導
    private(set) var sections: [MenuSection] = []
    private(set) var items: [MenuItem] = []
    private(set) var options: [MenuItemOption] = []
    private(set) var groupedItems: [SectionGroup] = []
    private var optionsByItem: [UUID: [MenuItemOption]] = [:]
    private var optionsById: [UUID: MenuItemOption] = [:]
    private var readingCache: [UUID: String] = [:]

    // 由 selections + members 推導
    private(set) var summaryLines: [OrderSummaryLine] = []
    private(set) var totalQuantity = 0
    private(set) var totalPrice: Decimal?
    private(set) var myTotalQuantity = 0
    private(set) var myTotalPrice: Decimal?
    private var mySelectionsByItem: [UUID: [MenuSelection]] = [:]

    private let roomRepository: any RoomRepository
    private let menuRepository: any MenuRepository
    private let orderRepository: any OrderRepository
    private var tasks: [Task<Void, Never>] = []

    init(session: RoomSession, roomRepository: any RoomRepository, menuRepository: any MenuRepository, orderRepository: any OrderRepository) {
        self.session = session
        self.roomRepository = roomRepository
        self.menuRepository = menuRepository
        self.orderRepository = orderRepository
    }

    var room: DiningRoom { session.room }
    var me: RoomMember { session.member }
    var isHost: Bool { session.member.isHost }

    struct SectionGroup: Identifiable {
        var section: MenuSection?
        var items: [MenuItem]
        var id: String { section?.id.uuidString ?? "__none__" }
        var title: String { section?.nameJapanese ?? "其他" }
        var subtitle: String? { section?.nameChinese }
    }

    // MARK: - 串流

    func start() {
        guard tasks.isEmpty else { return }
        let roomId = room.id
        tasks = [
            observe { [roomRepository] in await roomRepository.observeMembers(roomId: roomId) } apply: { [weak self] in self?.members = $0 },
            observe { [menuRepository] in await menuRepository.observeMenus(roomId: roomId) } apply: { [weak self] in
                self?.menus = $0
                self?.hasLoadedMenu = true
            },
            observe { [orderRepository] in await orderRepository.observeSelections(roomId: roomId) } apply: { [weak self] in self?.selections = $0 },
        ]
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    /// 串流結束（通常是斷線）→ 顯示白話錯誤，3 秒後重新訂閱。
    private func observe<Value: Sendable>(
        _ makeStream: @escaping @Sendable () async -> AsyncStream<Value>,
        apply: @escaping @MainActor (Value) -> Void
    ) -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                let stream = await makeStream()
                for await value in stream {
                    if Task.isCancelled { return }
                    apply(value)
                    self?.error = nil
                }
                if Task.isCancelled { return }
                self?.error = .syncUnavailable
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    // MARK: - 快取

    private func rebuildMenuCaches() {
        sections = menus.flatMap(\.sections)
        items = menus.flatMap(\.items)
        options = menus.flatMap(\.options)
        optionsById = Dictionary(options.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        optionsByItem = Dictionary(grouping: options, by: \.menuItemId).mapValues { $0.sorted { $0.sortOrder < $1.sortOrder } }

        var groups: [SectionGroup] = []
        for bundle in menus {
            for section in bundle.sections.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                let sectionItems = bundle.items.filter { $0.sectionId == section.id }.sorted { $0.sortOrder < $1.sortOrder }
                if !sectionItems.isEmpty { groups.append(SectionGroup(section: section, items: sectionItems)) }
            }
        }
        let loose = menus.flatMap { bundle in bundle.items.filter { $0.sectionId == nil } }.sorted { $0.sortOrder < $1.sortOrder }
        if !loose.isEmpty { groups.append(SectionGroup(section: nil, items: loose)) }
        groupedItems = groups

        // 房主才需要拼音：沒有拼音的菜在這台手機離線產生一次
        for item in items where isHost && item.reading?.nilIfBlank == nil && readingCache[item.id] == nil {
            if let romaji = JapaneseReading.romaji(for: item.japaneseName) { readingCache[item.id] = romaji }
        }
    }

    private func rebuildOrderCaches() {
        summaryLines = OrderSummaryBuilder.build(items: items, options: options, members: members, selections: selections)
        totalQuantity = OrderSummaryBuilder.totalQuantity(of: summaryLines)
        totalPrice = OrderSummaryBuilder.totalPrice(of: summaryLines)

        let mine = selections.filter { $0.memberId == me.id && $0.quantity > 0 }
        mySelectionsByItem = Dictionary(grouping: mine, by: \.menuItemId).mapValues { $0.sorted { $0.updatedAt < $1.updatedAt } }
        myTotalQuantity = mine.reduce(0) { $0 + $1.quantity }
        let itemsById = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var total = Decimal(0)
        var complete = !mine.isEmpty
        for selection in mine {
            guard let item = itemsById[selection.menuItemId], let unit = unitPrice(item: item, optionIds: selection.optionIds) else { complete = false; continue }
            total += unit * Decimal(selection.quantity)
        }
        myTotalPrice = complete ? total : nil
    }

    // MARK: - 菜單查詢

    func options(for item: MenuItem) -> [MenuItemOption] { optionsByItem[item.id] ?? [] }

    /// 顯示用拼音：只有房主（建立菜單的人）看得到，家人加入時不顯示。
    /// 資料有就用資料的，沒有就用本機產生的。
    func reading(for item: MenuItem) -> String? {
        guard isHost else { return nil }
        return item.reading?.nilIfBlank ?? readingCache[item.id]
    }

    func optionNames(for selection: MenuSelection) -> [MenuItemOption] {
        selection.optionIds.compactMap { optionsById[$0] }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func unitPrice(item: MenuItem, optionIds: [UUID]) -> Decimal? {
        guard let base = item.price else { return nil }
        return base + optionIds.compactMap { optionsById[$0]?.priceDelta }.reduce(Decimal(0), +)
    }

    // MARK: - 我的點餐

    func myQuantity(item: MenuItem, optionIds: [UUID] = []) -> Int {
        let key = optionIds.map(\.uuidString).sorted().joined(separator: "+")
        return mySelectionsByItem[item.id]?.first { $0.variantKey == key }?.quantity ?? 0
    }

    /// 我對這道菜點的所有組合（數量 > 0）
    func mySelections(for item: MenuItem) -> [MenuSelection] { mySelectionsByItem[item.id] ?? [] }

    /// 加減數量：先立刻改畫面（樂觀更新），再送出；失敗就還原並顯示錯誤。
    func adjust(item: MenuItem, optionIds: [UUID] = [], by delta: Int) async {
        let current = myQuantity(item: item, optionIds: optionIds)
        let target = max(0, min(99, current + delta))
        guard target != current else { return }

        let key = optionIds.map(\.uuidString).sorted().joined(separator: "+")
        let previous = selections
        if let index = selections.firstIndex(where: { $0.memberId == me.id && $0.menuItemId == item.id && $0.variantKey == key }) {
            selections[index].quantity = target
            selections[index].updatedAt = .now
        } else {
            selections.append(MenuSelection(roomId: room.id, memberId: me.id, menuItemId: item.id, optionIds: optionIds, quantity: target))
        }

        do {
            try await orderRepository.setQuantity(roomId: room.id, memberId: me.id, menuItemId: item.id, optionIds: optionIds, quantity: target)
        } catch {
            selections = previous
            self.error = UserFacingError.from(error)
        }
    }
}
