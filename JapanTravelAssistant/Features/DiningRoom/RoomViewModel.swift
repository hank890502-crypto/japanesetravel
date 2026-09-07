import Foundation
import Observation

/// 一個房間裡的所有狀態：成員、菜單、每個人的點餐。
/// 三條即時串流各自更新；斷線後串流結束會自動重連（重新訂閱並整份重抓）。
///
/// 生命週期：一個房間 session 只有一個 RoomViewModel（由 RoomSessionCoordinator 持有），
/// 點餐頁、本桌訂單、給店員看共用同一份；只有真正離開房間才 stop()。
///
/// 效能：分組、彙總、每道菜的選項、我的數量、拼音都在資料變動時算一次存起來，
/// 畫面重繪時只是查表，不會每一列都重新過濾整份資料。
@Observable
@MainActor
final class RoomViewModel {
    private(set) var session: RoomSession
    private(set) var members: [RoomMember] = [] { didSet { rebuildOrderCaches() } }
    private(set) var menus: [MenuBundle] = [] { didSet { rebuildMenuCaches(); rebuildOrderCaches() } }
    private(set) var selections: [MenuSelection] = [] { didSet { rebuildOrderCaches() } }
    private(set) var hasLoadedMenu = false
    private(set) var hasLoadedMembers = false
    private(set) var hasLoadedSelections = false
    /// 三份資料都到齊了（本桌訂單在這之前顯示「載入中」，而不是「還沒有人點東西」）
    var isReady: Bool { hasLoadedMenu && hasLoadedMembers && hasLoadedSelections }
    var error: UserFacingError?
    /// 房間已經結束（過期、房主關閉、這台手機已不是成員）。設定後串流停止、+ / − 不再送出。
    private(set) var roomEnded: UserFacingError?

    /// 回到房間時重新確認過身分，session 有更新（例如重新加入後成員 id 變了）→ 通知持有者存起來
    @ObservationIgnored var onSessionRestored: (@MainActor (RoomSession) -> Void)?
    /// 房間結束 → 通知持有者清掉 session、讓畫面顯示說明
    @ObservationIgnored var onRoomEnded: (@MainActor (UserFacingError) -> Void)?

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
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    // 在途的點餐寫入（每道菜每個組合一筆）：見 adjust()
    private struct PendingKey: Hashable { let menuItemId: UUID; let variantKey: String }
    private struct PendingWrite { var target: Int; var optionIds: [UUID]; var task: Task<Void, Never>? }
    @ObservationIgnored private var pendingWrites: [PendingKey: PendingWrite] = [:]
    /// 最後一次從伺服器拿到的完整選擇（失敗還原時用）
    @ObservationIgnored private var serverSelections: [MenuSelection] = []
    /// 寫入成功後再保護一小段時間：伺服器的變動通知與重抓可能還在路上、帶著舊值
    static let settleDelay: Duration = .milliseconds(1500)

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
        guard tasks.isEmpty, roomEnded == nil else { return }
        tasks = [Task { [weak self] in guard let self else { return }; await self.restoreThenObserve() }]
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    /// 先確認這台手機還是成員（身分變了會重新加入、房間結束會直接告知），再開三條串流。
    private func restoreThenObserve() async {
        do {
            let restored = try await roomRepository.restoreSession(session)
            if Task.isCancelled { return }
            if restored != session {
                session = restored
                onSessionRestored?(restored)
            }
        } catch let error as UserFacingError where error == .roomEnded || error == .roomNeedsRecreate {
            if Task.isCancelled { return }
            endRoom(error)
            return
        } catch {
            // 網路暫時不通等：照常訂閱，串流會顯示「無法同步」並自動重試
            if Task.isCancelled { return }
        }
        guard room.isJoinable else { endRoom(.roomEnded); return }

        let roomId = room.id
        let myMemberId = me.id
        tasks += [
            observe { [roomRepository] in await roomRepository.observeMembers(roomId: roomId) } apply: { [weak self] members in
                guard let self else { return }
                self.members = members
                self.hasLoadedMembers = true
                // 名單裡沒有我 = 房間被刪、這台手機已不是成員、或本機資料已清空 → 不要顯示一個空房間
                if !members.contains(where: { $0.id == myMemberId }) { self.endRoom(.roomEnded) }
            },
            observe { [menuRepository] in await menuRepository.observeMenus(roomId: roomId) } apply: { [weak self] in
                self?.menus = $0
                self?.hasLoadedMenu = true
            },
            observe { [orderRepository] in await orderRepository.observeSelections(roomId: roomId) } apply: { [weak self] in
                self?.applyServerSelections($0)
            },
            // 到期就結束（App 掛在背景好幾天回來也會觸發）
            Task { [weak self] in
                guard let expiresAt = self?.room.expiresAt else { return }
                let remaining = expiresAt.timeIntervalSinceNow
                if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
                guard !Task.isCancelled else { return }
                self?.endRoom(.roomEnded)
            },
        ]
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
                    guard let self, self.roomEnded == nil else { return }
                    if !self.room.isJoinable { self.endRoom(.roomEnded); return }
                    apply(value)
                    // 有資料進來代表同步恢復了；點餐失敗這類錯誤要留著給長輩看，不能被沖掉
                    if self.error == .syncUnavailable { self.error = nil }
                }
                if Task.isCancelled { return }
                guard let self, self.roomEnded == nil else { return }
                self.error = .syncUnavailable
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func endRoom(_ notice: UserFacingError) {
        guard roomEnded == nil else { return }
        roomEnded = notice
        stop()
        for key in pendingWrites.keys { pendingWrites[key]?.task?.cancel() }
        pendingWrites = [:]
        onRoomEnded?(notice)
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
        let key = MenuSelection.variantKey(for: optionIds)
        return mySelectionsByItem[item.id]?.first { $0.variantKey == key }?.quantity ?? 0
    }

    /// 我對這道菜點的所有組合（數量 > 0）
    func mySelections(for item: MenuItem) -> [MenuSelection] { mySelectionsByItem[item.id] ?? [] }

    /// 加減數量：先立刻改畫面（樂觀更新），再送出。
    ///
    /// 快速連按時每個 (菜, 組合) 只保留一個「目標值」，用一條序列化的寫入把最新目標送出（前一次送完再送下一次，中間的點按合併），
    /// 伺服器的重抓對在途的 key 一律以本機目標為準，所以畫面不會 0→1→2→1→2 跳動；
    /// 失敗只把這一道菜這個組合還原成最後一次伺服器值，不會連其他人或自己其他已成功的變更一起蓋掉。
    func adjust(item: MenuItem, optionIds: [UUID] = [], by delta: Int) async {
        guard roomEnded == nil else { return }
        let current = myQuantity(item: item, optionIds: optionIds)
        let target = max(0, min(99, current + delta))
        guard target != current else { return }

        let key = PendingKey(menuItemId: item.id, variantKey: MenuSelection.variantKey(for: optionIds))
        setLocalQuantity(item: item, optionIds: optionIds, quantity: target)

        if var pending = pendingWrites[key] {
            pending.target = target
            if let inFlight = pending.task {
                // 前一次還在送：只更新目標值，送完會接著送最新的
                pendingWrites[key] = pending
                await inFlight.value
                return
            }
            // 上一次已送完、還在保護期：直接再開一條
            let task = Task { [weak self] in guard let self else { return }; await self.flush(key: key, item: item, optionIds: optionIds) }
            pending.task = task
            pendingWrites[key] = pending
            await task.value
            return
        }
        let task = Task { [weak self] in guard let self else { return }; await self.flush(key: key, item: item, optionIds: optionIds) }
        pendingWrites[key] = PendingWrite(target: target, optionIds: optionIds, task: task)
        await task.value
    }

    /// 把這個 key 的最新目標值送到伺服器，直到目標值沒有再變為止。
    private func flush(key: PendingKey, item: MenuItem, optionIds: [UUID]) async {
        var sent: Int?
        while let target = pendingWrites[key]?.target, target != sent {
            if Task.isCancelled { return }
            do {
                try await orderRepository.setQuantity(roomId: room.id, memberId: me.id, menuItemId: item.id, optionIds: optionIds, quantity: target)
                sent = target
                rememberServerQuantity(item: item, optionIds: optionIds, quantity: target)
            } catch {
                pendingWrites[key] = nil
                let serverQuantity = serverSelections.first { $0.memberId == me.id && $0.menuItemId == item.id && $0.variantKey == key.variantKey }?.quantity ?? 0
                setLocalQuantity(item: item, optionIds: optionIds, quantity: serverQuantity)
                self.error = UserFacingError.from(error)
                return
            }
        }
        pendingWrites[key]?.task = nil
        Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard let self, self.pendingWrites[key]?.task == nil else { return }
            self.pendingWrites[key] = nil
        }
    }

    /// 伺服器整份資料進來：在途（或剛送完還在保護期）的 key 以本機目標值為準。
    private func applyServerSelections(_ incoming: [MenuSelection]) {
        serverSelections = incoming
        var merged = incoming
        for (key, pending) in pendingWrites {
            if let index = merged.firstIndex(where: { $0.memberId == me.id && $0.menuItemId == key.menuItemId && $0.variantKey == key.variantKey }) {
                merged[index].quantity = pending.target
            } else {
                merged.append(MenuSelection(roomId: room.id, memberId: me.id, menuItemId: key.menuItemId, optionIds: pending.optionIds, quantity: pending.target))
            }
        }
        selections = merged
        hasLoadedSelections = true
    }

    private func setLocalQuantity(item: MenuItem, optionIds: [UUID], quantity: Int) {
        let key = MenuSelection.variantKey(for: optionIds)
        if let index = selections.firstIndex(where: { $0.memberId == me.id && $0.menuItemId == item.id && $0.variantKey == key }) {
            selections[index].quantity = quantity
            selections[index].updatedAt = .now
        } else {
            selections.append(MenuSelection(roomId: room.id, memberId: me.id, menuItemId: item.id, optionIds: optionIds, quantity: quantity))
        }
    }

    /// 寫入成功 = 伺服器現在是這個值；之後若別的寫入失敗，還原到這裡而不是更早的快照。
    private func rememberServerQuantity(item: MenuItem, optionIds: [UUID], quantity: Int) {
        let key = MenuSelection.variantKey(for: optionIds)
        if let index = serverSelections.firstIndex(where: { $0.memberId == me.id && $0.menuItemId == item.id && $0.variantKey == key }) {
            serverSelections[index].quantity = quantity
        } else {
            serverSelections.append(MenuSelection(roomId: room.id, memberId: me.id, menuItemId: item.id, optionIds: optionIds, quantity: quantity))
        }
    }
}
