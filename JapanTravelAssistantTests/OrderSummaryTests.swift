import Foundation
import Testing
@testable import JapanTravelAssistant

@Suite("點餐彙總")
struct OrderSummaryTests {
    @Test("每個人各自的數量會加總，且保留誰點了什麼")
    func buildsSummary() {
        let roomId = UUID()
        let menuId = UUID()
        let karaage = MenuItem(menuId: menuId, japaneseName: "若どり唐揚げ", chineseName: "炸嫩雞", price: 540, sortOrder: 0)
        let tebasaki = MenuItem(menuId: menuId, japaneseName: "手羽先", price: 430, sortOrder: 1)
        let kushikatsu = MenuItem(menuId: menuId, japaneseName: "味噌串カツ", price: 540, sortOrder: 2)

        let me = RoomMember(roomId: roomId, userId: UUID(), displayName: "我", isHost: true, createdAt: .now.addingTimeInterval(-30))
        let mom = RoomMember(roomId: roomId, userId: UUID(), displayName: "媽媽", createdAt: .now.addingTimeInterval(-20))
        let dad = RoomMember(roomId: roomId, userId: UUID(), displayName: "爸爸", createdAt: .now.addingTimeInterval(-10))

        let selections = [
            MenuSelection(roomId: roomId, memberId: mom.id, menuItemId: karaage.id, quantity: 1),
            MenuSelection(roomId: roomId, memberId: dad.id, menuItemId: tebasaki.id, quantity: 2),
            MenuSelection(roomId: roomId, memberId: me.id, menuItemId: kushikatsu.id, quantity: 1),
            MenuSelection(roomId: roomId, memberId: me.id, menuItemId: karaage.id, quantity: 0), // 取消了
        ]

        let lines = OrderSummaryBuilder.build(items: [karaage, tebasaki, kushikatsu], members: [me, mom, dad], selections: selections)

        #expect(lines.map(\.menuItem.japaneseName) == ["若どり唐揚げ", "手羽先", "味噌串カツ"])
        #expect(lines.map(\.totalQuantity) == [1, 2, 1])
        #expect(OrderSummaryBuilder.totalQuantity(of: lines) == 4)
        #expect(lines[0].byMember.map(\.member.displayName) == ["媽媽"])
        #expect(lines[1].byMember.first?.quantity == 2)
    }

    @Test("InMemoryOrderRepository：每人一列、可觀察更新")
    func repositoryKeepsPerMemberRows() async throws {
        let repo = InMemoryOrderRepository()
        let roomId = UUID()
        let itemId = UUID()
        let a = UUID()
        let b = UUID()

        let stream = await repo.observeSelections(roomId: roomId)
        var iterator = stream.makeAsyncIterator()
        let initial = await iterator.next()
        #expect(initial?.isEmpty == true)

        try await repo.setQuantity(roomId: roomId, memberId: a, menuItemId: itemId, quantity: 2)
        try await repo.setQuantity(roomId: roomId, memberId: b, menuItemId: itemId, quantity: 1)
        try await repo.setQuantity(roomId: roomId, memberId: a, menuItemId: itemId, quantity: 3)

        let all = try await repo.selections(roomId: roomId)
        #expect(all.count == 2)
        #expect(all.first { $0.memberId == a }?.quantity == 3)
        #expect(all.first { $0.memberId == b }?.quantity == 1)
        #expect(all.reduce(0) { $0 + $1.quantity } == 4)
    }

    @Test("InMemoryRoomRepository：建房、加入、找不到")
    func roomLifecycle() async throws {
        let host = InMemoryRoomRepository(currentUserId: UUID())
        let session = try await host.createRoom(name: "酒津屋晚餐", hostDisplayName: "我")
        #expect(session.member.isHost)
        #expect(RoomCodeGenerator.isValid(session.room.roomCode))

        let joined = try await host.joinRoom(code: session.room.roomCode.lowercased(), displayName: "我改名")
        #expect(joined.member.id == session.member.id)
        #expect(joined.member.displayName == "我改名")

        await #expect(throws: UserFacingError.self) {
            _ = try await host.joinRoom(code: "ZZZZZZ", displayName: "路人")
        }
    }
}
