import Foundation
import Testing
@testable import JapanTravelAssistant

@Suite("打開連結與旅程檔")
@MainActor
struct AppRouterTests {
    private func makeInbox() throws -> URL {
        let inbox = FileManager.default.temporaryDirectory.appendingPathComponent("AppRouterTests-\(UUID().uuidString)/Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        return inbox
    }

    private func samplePackageData() throws -> Data {
        let store = PlaceStore(directory: nil)
        let trip = store.addTrip(name: "9 月名古屋")
        store.add(Place(name: "名古屋城", category: .sight), to: trip.id)
        return try #require(store.package(for: trip.id)).encoded()
    }

    @Test("打開 .jptrip：讀得懂 → 等使用者確認，並回到能顯示確認畫面的地方；Inbox 裡的檔案讀完就刪")
    func opensTripFileAndCleansInbox() throws {
        let inbox = try makeInbox()
        let file = inbox.appendingPathComponent("旅程.jptrip")
        try samplePackageData().write(to: file)
        let router = AppRouter()
        router.inboxDirectory = inbox
        router.path = [.understandHub, .restaurantHub, .room]
        router.staffDisplay = StaffDisplayContent(japanese: "テスト")

        router.handle(file)
        #expect(router.receivedTrip?.trip.name == "9 月名古屋")
        #expect(router.prompt == nil)
        #expect(router.staffDisplay == nil)
        #expect(router.path == [.places])
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("打開壞掉的 .jptrip：不會沒反應，會有白話提示；檔案一樣清掉")
    func brokenTripFileShowsMessage() throws {
        let inbox = try makeInbox()
        let file = inbox.appendingPathComponent("壞掉.jptrip")
        try Data("這不是旅程檔".utf8).write(to: file)
        let router = AppRouter()
        router.inboxDirectory = inbox

        router.handle(file)
        #expect(router.receivedTrip == nil)
        #expect(router.prompt == .message(.unreadableTripFile))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("新版 App 做的旅程檔：提示先更新 App")
    func newerTripFileAsksToUpdate() throws {
        let inbox = try makeInbox()
        let file = inbox.appendingPathComponent("新版.jptrip")
        try Data(#"{"version":2,"trip":{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"x","mustHave":1},"places":[],"stops":[]}"#.utf8).write(to: file)
        let router = AppRouter()
        router.inboxDirectory = inbox
        router.handle(file)
        guard case .message(let error)? = router.prompt else {
            Issue.record("應該要有提示")
            return
        }
        #expect(error.title.contains("新版"))
    }

    @Test("不在 Inbox 的檔案不會被刪")
    func doesNotDeleteFilesOutsideInbox() throws {
        let inbox = try makeInbox()
        let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent("AppRouterTests-outside-\(UUID().uuidString).jptrip")
        try samplePackageData().write(to: elsewhere)
        let router = AppRouter()
        router.inboxDirectory = inbox
        router.handle(elsewhere)
        #expect(router.receivedTrip != nil)
        #expect(FileManager.default.fileExists(atPath: elsewhere.path))
        try? FileManager.default.removeItem(at: elsewhere)
    }

    @Test("房間連結：沒在房間裡 → 去加入頁並帶代碼；不合法的連結不理")
    func joinLinkWhenNotInRoom() {
        let router = AppRouter(webGuestHost: "user.github.io")
        router.handle(URL(string: "jptravel://join?code=a8f3k2")!, currentRoom: nil)
        #expect(router.path == [.understandHub, .restaurantHub, .joinRoom(code: "A8F3K2")])

        let router2 = AppRouter()
        router2.handle(URL(string: "https://example.com/?code=PROMO2026")!, currentRoom: nil)
        #expect(router2.path.isEmpty && router2.prompt == nil)
    }

    @Test("房間連結：已經在同一個房間 → 直接回到點餐畫面；在別的房間 → 先問要不要離開")
    func joinLinkWhileInRoom() {
        let room = DiningRoom(name: "酒津屋晚餐", roomCode: "A8F3K2", hostUserId: UUID())
        let session = RoomSession(room: room, member: RoomMember(roomId: room.id, userId: UUID(), displayName: "我"))
        let router = AppRouter()
        router.path = [.understandHub, .restaurantHub, .room, .orderSummary]
        router.handle(URL(string: "jptravel://join?code=A8F3K2")!, currentRoom: session)
        #expect(router.path == [.understandHub, .restaurantHub, .room])
        #expect(router.prompt == nil)

        // 另一個房間的連結：先問，路徑不變
        router.handle(URL(string: "jptravel://join?code=B7C2D4")!, currentRoom: session)
        #expect(router.prompt == .switchRoom(code: "B7C2D4", currentRoomName: "酒津屋晚餐"))
        #expect(router.path == [.understandHub, .restaurantHub, .room])

        // 使用者確認離開 → 才去加入頁
        router.confirmSwitchRoom()
        #expect(router.prompt == nil)
        #expect(router.path == [.understandHub, .restaurantHub, .joinRoom(code: "B7C2D4")])

        // 舊房間已經關了（不能再加入）就不用問
        var closed = room
        closed.status = .closed
        let router2 = AppRouter()
        router2.handle(URL(string: "jptravel://join?code=B7C2D4")!, currentRoom: RoomSession(room: closed, member: session.member))
        #expect(router2.prompt == nil)
        #expect(router2.path == [.understandHub, .restaurantHub, .joinRoom(code: "B7C2D4")])
    }
}
