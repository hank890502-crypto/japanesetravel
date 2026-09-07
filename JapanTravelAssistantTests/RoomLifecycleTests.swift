import Foundation
import Testing
@testable import JapanTravelAssistant

/// 可以放慢、可以故意失敗的 OrderRepository，用來測快速連按與失敗還原。
actor DelayedOrderRepository: OrderRepository {
    private let inner = InMemoryOrderRepository()
    var delay: Duration
    var failNext = false
    private(set) var sentQuantities: [Int] = []

    init(delay: Duration = .zero) { self.delay = delay }

    func setDelay(_ delay: Duration) { self.delay = delay }
    func failNextWrite() { failNext = true }

    func setQuantity(roomId: UUID, memberId: UUID, menuItemId: UUID, optionIds: [UUID], quantity: Int) async throws {
        sentQuantities.append(quantity)
        if delay > .zero { try? await Task.sleep(for: delay) }
        if failNext {
            failNext = false
            throw UserFacingError(title: "點餐沒有送出", message: "測試用的失敗。")
        }
        try await inner.setQuantity(roomId: roomId, memberId: memberId, menuItemId: menuItemId, optionIds: optionIds, quantity: quantity)
    }

    func selections(roomId: UUID) async throws -> [MenuSelection] { try await inner.selections(roomId: roomId) }
    func observeSelections(roomId: UUID) async -> AsyncStream<[MenuSelection]> { await inner.observeSelections(roomId: roomId) }
}

@MainActor
private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
    for _ in 0..<100 where !condition() {
        try? await Task.sleep(for: .milliseconds(20))
    }
}

@MainActor
private func makeRoom(orderRepo: any OrderRepository) async throws -> (RoomViewModel, InMemoryRoomRepository, MenuBundle) {
    let roomRepo = InMemoryRoomRepository(currentUserId: UUID())
    let menuRepo = InMemoryMenuRepository()
    let session = try await roomRepo.createRoom(name: "酒津屋晚餐", hostDisplayName: "我")
    let bundle = try await menuRepo.saveMenu(MenuDraft(items: [
        MenuItemDraft(japaneseName: "若どり唐揚げ", priceText: "540"),
        MenuItemDraft(japaneseName: "手羽先", priceText: "430"),
    ]).toBundle(), toRoom: session.room.id)
    let vm = RoomViewModel(session: session, roomRepository: roomRepo, menuRepository: menuRepo, orderRepository: orderRepo)
    return (vm, roomRepo, bundle)
}

@Suite("快速連按 + / −（在途寫入序列化）")
@MainActor
struct RoomOrderingTests {
    @Test("連按兩下 +：畫面一路是 1→2，伺服器依序收到 1、2，最後兩邊都是 2")
    func rapidTapsAreSerialized() async throws {
        let repo = DelayedOrderRepository(delay: .milliseconds(80))
        let (vm, _, bundle) = try await makeRoom(orderRepo: repo)
        vm.start(); defer { vm.stop() }
        await waitUntil { vm.isReady }
        let item = bundle.items[0]

        async let first: Void = vm.adjust(item: item, by: 1)
        try? await Task.sleep(for: .milliseconds(10))
        #expect(vm.myQuantity(item: item) == 1)
        async let second: Void = vm.adjust(item: item, by: 1)
        try? await Task.sleep(for: .milliseconds(10))
        #expect(vm.myQuantity(item: item) == 2)
        _ = await (first, second)

        #expect(vm.myQuantity(item: item) == 2)
        #expect(await repo.sentQuantities == [1, 2])
        #expect(try await repo.selections(roomId: vm.room.id).first?.quantity == 2)
        #expect(vm.error == nil)
    }

    @Test("連按三下：中間的點按合併，只送兩次（1 與 3）")
    func intermediateTapsCoalesce() async throws {
        let repo = DelayedOrderRepository(delay: .milliseconds(80))
        let (vm, _, bundle) = try await makeRoom(orderRepo: repo)
        vm.start(); defer { vm.stop() }
        await waitUntil { vm.isReady }
        let item = bundle.items[0]

        async let a: Void = vm.adjust(item: item, by: 1)
        try? await Task.sleep(for: .milliseconds(10))
        async let b: Void = vm.adjust(item: item, by: 1)
        try? await Task.sleep(for: .milliseconds(10))
        async let c: Void = vm.adjust(item: item, by: 1)
        _ = await (a, b, c)

        #expect(vm.myQuantity(item: item) == 3)
        #expect(await repo.sentQuantities == [1, 3])
        #expect(try await repo.selections(roomId: vm.room.id).first?.quantity == 3)
    }

    @Test("伺服器重抓帶著舊值時，在途的那道菜以本機目標為準，不會 2→1→2 跳動")
    func serverRefetchDoesNotClobberInFlightValue() async throws {
        let repo = DelayedOrderRepository(delay: .milliseconds(150))
        let (vm, _, bundle) = try await makeRoom(orderRepo: repo)
        vm.start(); defer { vm.stop() }
        await waitUntil { vm.isReady }
        let item = bundle.items[0]

        async let first: Void = vm.adjust(item: item, by: 1)
        try? await Task.sleep(for: .milliseconds(10))
        async let second: Void = vm.adjust(item: item, by: 1)
        // 第一次寫入完成時 InMemory 會廣播 quantity=1；此時第二次還在途，畫面必須維持 2
        try? await Task.sleep(for: .milliseconds(200))
        #expect(vm.myQuantity(item: item) == 2)
        _ = await (first, second)
        #expect(vm.myQuantity(item: item) == 2)
    }

    @Test("失敗只還原那一道菜，其他人與自己其他已成功的點餐都留著；錯誤不會被後續同步沖掉")
    func failureRestoresOnlyThatKey() async throws {
        let repo = DelayedOrderRepository()
        let (vm, roomRepo, bundle) = try await makeRoom(orderRepo: repo)
        vm.start(); defer { vm.stop() }
        await waitUntil { vm.isReady }
        let karaage = bundle.items[0], tebasaki = bundle.items[1]

        let mom = await roomRepo.addMember(roomId: vm.room.id, displayName: "媽媽")
        try await repo.setQuantity(roomId: vm.room.id, memberId: mom.id, menuItemId: karaage.id, optionIds: [], quantity: 2)
        await vm.adjust(item: karaage, by: 1)               // 成功：1
        await waitUntil { vm.totalQuantity == 3 }

        await repo.failNextWrite()
        await vm.adjust(item: tebasaki, by: 1)              // 失敗：還原成 0
        #expect(vm.myQuantity(item: tebasaki) == 0)
        #expect(vm.myQuantity(item: karaage) == 1)          // 自己成功的沒有被蓋掉
        #expect(vm.summaryLines.first { $0.menuItem.id == karaage.id }?.totalQuantity == 3)   // 媽媽的也還在
        #expect(vm.error?.title == "點餐沒有送出")

        // 別人再點東西（串流送資料進來）不會把點餐失敗的提示清掉
        try await repo.setQuantity(roomId: vm.room.id, memberId: mom.id, menuItemId: tebasaki.id, optionIds: [], quantity: 1)
        await waitUntil { vm.totalQuantity == 4 }
        #expect(vm.error?.title == "點餐沒有送出")
    }

    @Test("失敗還原到「最後一次伺服器值」而不是更早的快照")
    func failureRestoresToLastServerValue() async throws {
        let repo = DelayedOrderRepository()
        let (vm, _, bundle) = try await makeRoom(orderRepo: repo)
        vm.start(); defer { vm.stop() }
        await waitUntil { vm.isReady }
        let item = bundle.items[0]

        await vm.adjust(item: item, by: 1)
        await vm.adjust(item: item, by: 1)                  // 伺服器 = 2
        await repo.failNextWrite()
        await vm.adjust(item: item, by: 1)                  // 3 失敗 → 回到 2
        #expect(vm.myQuantity(item: item) == 2)
        #expect(try await repo.selections(roomId: vm.room.id).first?.quantity == 2)
    }
}

@Suite("房間結束與身分確認")
@MainActor
struct RoomEndTests {
    @Test("重開 App 後房間已不存在（本機模式）：回報「已結束」，不會顯示空房間")
    func restoreOfMissingRoomEnds() async throws {
        let roomRepo = InMemoryRoomRepository(currentUserId: UUID())
        let room = DiningRoom(name: "昨天的", roomCode: "A8F3K2", hostUserId: UUID())
        let session = RoomSession(room: room, member: RoomMember(roomId: room.id, userId: room.hostUserId, displayName: "我", isHost: true))
        let vm = RoomViewModel(session: session, roomRepository: roomRepo, menuRepository: InMemoryMenuRepository(), orderRepository: InMemoryOrderRepository())
        var ended: UserFacingError?
        vm.onRoomEnded = { ended = $0 }
        vm.start(); defer { vm.stop() }
        await waitUntil { ended != nil }
        #expect(ended == .roomEnded)
        #expect(vm.roomEnded == .roomEnded)
        #expect(!vm.hasLoadedMenu)
    }

    @Test("名單裡沒有我（成員被移除）→ 房間結束、+ 不再送出")
    func removedMemberEnds() async throws {
        let repo = DelayedOrderRepository()
        let (vm, roomRepo, bundle) = try await makeRoom(orderRepo: repo)
        var ended: UserFacingError?
        vm.onRoomEnded = { ended = $0 }
        vm.start(); defer { vm.stop() }
        await waitUntil { vm.isReady }
        #expect(ended == nil)

        await roomRepo.removeMember(id: vm.me.id)
        await waitUntil { ended != nil }
        #expect(ended == .roomEnded)
        await vm.adjust(item: bundle.items[0], by: 1)
        #expect(await repo.sentQuantities.isEmpty)
    }

    @Test("過期的房間：進入時立刻結束；家人身分變了會重新加入，房主身分變了要重新建立")
    func expiredAndIdentityChange() async throws {
        let roomRepo = InMemoryRoomRepository(currentUserId: UUID())
        let host = try await roomRepo.createRoom(name: "測試", hostDisplayName: "我")

        // 本機存的到期時間過了、但伺服器說房間還開著 → 以伺服器為準，不會結束（拿到最新的房間資料）
        var staleRoom = host.room
        staleRoom.expiresAt = .now.addingTimeInterval(-60)
        let refreshed = try await roomRepo.restoreSession(RoomSession(room: staleRoom, member: host.member))
        #expect(refreshed.room.isJoinable)

        // 伺服器上真的過期了 → 進入時立刻結束
        let expiredRepo = InMemoryRoomRepository(currentUserId: UUID())
        let expired = try await expiredRepo.createRoom(name: "昨天的", hostDisplayName: "我")
        await expiredRepo.expireRoom(id: expired.room.id)
        let expiredVM = RoomViewModel(session: expired, roomRepository: expiredRepo, menuRepository: InMemoryMenuRepository(), orderRepository: InMemoryOrderRepository())
        var ended: UserFacingError?
        expiredVM.onRoomEnded = { ended = $0 }
        expiredVM.start(); defer { expiredVM.stop() }
        await waitUntil { ended != nil }
        #expect(ended == .roomEnded)

        // 家人：本機存的成員已不在名單裡（身分變了）→ 用代碼重新加入，拿到新的成員
        let staleGuest = RoomMember(roomId: host.room.id, userId: UUID(), displayName: "媽媽")
        let restored = try await roomRepo.restoreSession(RoomSession(room: host.room, member: staleGuest))
        #expect(restored.member.id != staleGuest.id)
        #expect(restored.member.displayName == "媽媽")
        #expect(restored.room.id == host.room.id)

        // 房主：身分變了拿不回房間
        let staleHost = RoomMember(roomId: host.room.id, userId: UUID(), displayName: "我", isHost: true)
        do {
            _ = try await roomRepo.restoreSession(RoomSession(room: host.room, member: staleHost))
            Issue.record("房主身分變了應該要求重新建立")
        } catch let error as UserFacingError {
            #expect(error == .roomNeedsRecreate)
        }

        // 同一個人：回傳同一位成員
        let same = try await roomRepo.restoreSession(host)
        #expect(same.member.id == host.member.id)
    }

    @Test("稱呼超過 30 字會被截斷")
    func displayNameClamp() async throws {
        let long = String(repeating: "陳", count: 45)
        #expect(RoomMember.clampDisplayName(long).count == RoomMember.maxDisplayNameLength)
        #expect(RoomMember.clampDisplayName("媽媽") == "媽媽")
        let repo = InMemoryRoomRepository(currentUserId: UUID())
        let session = try await repo.createRoom(name: "測試", hostDisplayName: long)
        #expect(session.member.displayName.count == 30)
        let joined = try await repo.joinRoom(code: session.room.roomCode, displayName: long + "！")
        #expect(joined.member.displayName.count == 30)
    }
}

@Suite("RoomSessionCoordinator：一個房間只有一份 ViewModel")
@MainActor
struct RoomSessionCoordinatorTests {
    private func makeCoordinator() async throws -> (RoomSessionCoordinator, DiningSessionStore, InMemoryRoomRepository, RoomSession) {
        let defaults = UserDefaults(suiteName: "RoomSessionCoordinatorTests.\(UUID().uuidString)")!
        let store = DiningSessionStore(defaults: defaults)
        let roomRepo = InMemoryRoomRepository(currentUserId: UUID())
        let session = try await roomRepo.createRoom(name: "酒津屋晚餐", hostDisplayName: "我")
        let coordinator = RoomSessionCoordinator(sessionStore: store, roomRepository: roomRepo, menuRepository: InMemoryMenuRepository(), orderRepository: InMemoryOrderRepository())
        return (coordinator, store, roomRepo, session)
    }

    @Test("enter 後立刻有 ViewModel；重複讀取是同一份；leave 才清掉")
    func singleViewModelPerSession() async throws {
        let (coordinator, store, _, session) = try await makeCoordinator()
        #expect(coordinator.viewModel == nil)
        coordinator.enter(session)
        let first = try #require(coordinator.viewModel)
        #expect(store.current == session)
        // 模擬進出畫面、打開 cover：只是再讀一次，不會重建
        #expect(coordinator.viewModel === first)
        coordinator.sync()
        #expect(coordinator.viewModel === first)
        await waitUntil { first.isReady }
        #expect(first.members.count == 1)

        coordinator.leave()
        #expect(coordinator.viewModel == nil)
        #expect(store.current == nil)
    }

    @Test("session 從別處被清掉（例如啟動時判定過期）→ ViewModel 跟著停掉")
    func followsSessionStore() async throws {
        let (coordinator, store, _, session) = try await makeCoordinator()
        coordinator.enter(session)
        let vm = try #require(coordinator.viewModel)
        await waitUntil { vm.isReady }
        store.leave()
        await waitUntil { coordinator.viewModel == nil }
        #expect(coordinator.viewModel == nil)
    }

    @Test("房間結束：session 清掉、留下說明給長輩看，按回到餐廳後消失")
    func endedNotice() async throws {
        let (coordinator, store, roomRepo, session) = try await makeCoordinator()
        coordinator.enter(session)
        let vm = try #require(coordinator.viewModel)
        await waitUntil { vm.isReady }
        await roomRepo.removeMember(id: session.member.id)
        await waitUntil { coordinator.endedNotice != nil }
        #expect(coordinator.endedNotice == .roomEnded)
        #expect(coordinator.viewModel == nil)
        #expect(store.current == nil)
        coordinator.dismissEndedNotice()
        #expect(coordinator.endedNotice == nil)
    }

    @Test("過期的 session 一進來就結束，不會建 ViewModel")
    func expiredSessionEndsImmediately() async throws {
        let (coordinator, store, _, session) = try await makeCoordinator()
        var expired = session
        expired.room.expiresAt = .now.addingTimeInterval(-1)
        coordinator.enter(expired)
        #expect(coordinator.viewModel == nil)
        #expect(coordinator.endedNotice == .roomEnded)
        #expect(store.current == nil)
    }
}
