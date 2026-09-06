import Foundation
import Testing
@testable import JapanTravelAssistant

@Suite("多人點餐 ViewModel")
@MainActor
struct RoomViewModelTests {
    private func makeRoom() async throws -> (RoomViewModel, InMemoryRoomRepository, InMemoryMenuRepository, InMemoryOrderRepository, MenuBundle) {
        let roomRepo = InMemoryRoomRepository(currentUserId: UUID())
        let menuRepo = InMemoryMenuRepository()
        let orderRepo = InMemoryOrderRepository()
        let session = try await roomRepo.createRoom(name: "酒津屋晚餐", hostDisplayName: "我")
        let draft = MenuDraft(items: [
            MenuItemDraft(japaneseName: "若どり唐揚げ", chineseName: "炸嫩雞", priceText: "540", sectionName: "揚げ物"),
            MenuItemDraft(japaneseName: "手羽先", priceText: "430", sectionName: "揚げ物"),
            MenuItemDraft(japaneseName: "味噌串カツ", priceText: "540", options: [
                MenuOptionDraft(groupName: "份量", japaneseName: "大盛り", chineseName: "大份", priceDeltaText: "+150"),
            ]),
        ])
        let bundle = try await menuRepo.saveMenu(draft.toBundle(), toRoom: session.room.id)
        let vm = RoomViewModel(session: session, roomRepository: roomRepo, menuRepository: menuRepo, orderRepository: orderRepo)
        return (vm, roomRepo, menuRepo, orderRepo, bundle)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<50 where !condition() {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("完整情境：媽媽、爸爸、我各自點，房主看到彙總 4 份")
    func fullScenario() async throws {
        let (vm, roomRepo, _, orderRepo, bundle) = try await makeRoom()
        vm.start()
        defer { vm.stop() }
        await waitUntil { vm.hasLoadedMenu && vm.members.count == 1 }
        #expect(vm.items.count == 3)
        #expect(vm.groupedItems.map(\.title) == ["揚げ物", "其他"])

        let mom = await roomRepo.addMember(roomId: vm.room.id, displayName: "媽媽")
        let dad = await roomRepo.addMember(roomId: vm.room.id, displayName: "爸爸")
        await waitUntil { vm.members.count == 3 }

        let karaage = bundle.items[0], tebasaki = bundle.items[1], kushikatsu = bundle.items[2]
        let large = bundle.options[0]
        try await orderRepo.setQuantity(roomId: vm.room.id, memberId: mom.id, menuItemId: karaage.id, optionIds: [], quantity: 1)
        try await orderRepo.setQuantity(roomId: vm.room.id, memberId: dad.id, menuItemId: tebasaki.id, optionIds: [], quantity: 2)
        await vm.adjust(item: kushikatsu, optionIds: [large.id], by: 1)
        await waitUntil { vm.totalQuantity == 4 }

        #expect(vm.myQuantity(item: kushikatsu, optionIds: [large.id]) == 1)
        #expect(vm.myTotalQuantity == 1)
        let lines = vm.summaryLines
        #expect(lines.map(\.totalQuantity) == [1, 2, 1])
        #expect(lines[2].staffDisplayName == "味噌串カツ（大盛り）")
        #expect(lines[2].unitPrice == 690)
        #expect(vm.totalPrice.map { NSDecimalNumber(decimal: $0).intValue } == 540 + 860 + 690)
        #expect(lines[0].byMember.first?.member.displayName == "媽媽")
    }

    @Test("樂觀更新：按 + 立刻變 1，按 − 回到 0，不會變負")
    func optimisticAdjust() async throws {
        let (vm, _, _, _, bundle) = try await makeRoom()
        vm.start()
        defer { vm.stop() }
        await waitUntil { vm.hasLoadedMenu }
        let item = bundle.items[0]
        await vm.adjust(item: item, by: 1)
        #expect(vm.myQuantity(item: item) == 1)
        await vm.adjust(item: item, by: -1)
        await vm.adjust(item: item, by: -1)
        #expect(vm.myQuantity(item: item) == 0)
    }

    @Test("房間狀態會存起來，重開 App 還在")
    func sessionPersists() throws {
        let defaults = UserDefaults(suiteName: "RoomViewModelTests")!
        defaults.removePersistentDomain(forName: "RoomViewModelTests")
        let store = DiningSessionStore(defaults: defaults)
        let room = DiningRoom(name: "測試", roomCode: "A8F3K2", hostUserId: UUID())
        store.current = RoomSession(room: room, member: RoomMember(roomId: room.id, userId: room.hostUserId, displayName: "我", isHost: true))
        let reloaded = DiningSessionStore(defaults: defaults)
        #expect(reloaded.current?.room.roomCode == "A8F3K2")
        reloaded.leave()
        #expect(DiningSessionStore(defaults: defaults).current == nil)
    }

    @Test("Postgres 日期格式都能解析")
    func postgresDates() {
        #expect(SupabaseCoding.parsePostgresDate("2026-09-07T01:23:45.123456+00:00") != nil)
        #expect(SupabaseCoding.parsePostgresDate("2026-09-07T01:23:45+00:00") != nil)
        #expect(SupabaseCoding.parsePostgresDate("2026-09-07 01:23:45.12+00") != nil)
        #expect(SupabaseCoding.parsePostgresDate("2026-09-07T01:23:45Z") != nil)
        #expect(SupabaseCoding.parsePostgresDate("不是日期") == nil)
    }
}

@Suite("拼音只給房主")
@MainActor
struct ReadingVisibilityTests {
    @Test("房主看得到拼音，加入的家人看不到")
    func hostOnly() async throws {
        let hostRepo = InMemoryRoomRepository(currentUserId: UUID())
        let menuRepo = InMemoryMenuRepository()
        let orderRepo = InMemoryOrderRepository()
        let host = try await hostRepo.createRoom(name: "測試", hostDisplayName: "我", preferredCode: "0000")
        let bundle = try await menuRepo.saveMenu(MenuDraft(items: [MenuItemDraft(japaneseName: "とんかつ", priceText: "540", reading: "tonkatsu")]).toBundle(), toRoom: host.room.id)
        let item = bundle.items[0]

        let hostVM = RoomViewModel(session: host, roomRepository: hostRepo, menuRepository: menuRepo, orderRepository: orderRepo)
        hostVM.start(); defer { hostVM.stop() }
        for _ in 0..<50 where !hostVM.hasLoadedMenu { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(hostVM.reading(for: item) == "tonkatsu")

        let guestMember = await hostRepo.addMember(roomId: host.room.id, displayName: "媽媽")
        let guestVM = RoomViewModel(session: RoomSession(room: host.room, member: guestMember), roomRepository: hostRepo, menuRepository: menuRepo, orderRepository: orderRepo)
        guestVM.start(); defer { guestVM.stop() }
        for _ in 0..<50 where !guestVM.hasLoadedMenu { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(guestVM.reading(for: item) == nil)
    }
}
