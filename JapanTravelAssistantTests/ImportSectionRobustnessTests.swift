import Foundation
import Testing
@testable import JapanTravelAssistant

@Suite("匯入：分類行的各種寫法")
struct ImportSectionRobustnessTests {
    @Test("新格式「分類 | 日文 | 中文」")
    func markerFormat() {
        let items = MenuImportParser.parse("""
        分類 | 揚げ物 | 炸物
        若どり唐揚げ | 日式炸嫩雞 | 540 | | wakadori karaage
        分類：ドリンク | 飲料
        生ビール | 生啤酒 | 650
        """)
        #expect(items.map(\.section) == ["揚げ物", "ドリンク"])
        #expect(items.map(\.sectionChinese) == ["炸物", "飲料"])
        #expect(items[0].reading == "wakadori karaage")
    }

    @Test("從 ChatGPT App 複製：## 被吃掉、變粗體、只剩「揚げ物 | 炸物」")
    func markdownStripped() {
        let items = MenuImportParser.parse("""
        菜單開始
        揚げ物 | 炸物
        若どり唐揚げ | 日式炸嫩雞 | 540 |
        **焼き物 | 烤物**
        ねぎま | 蔥段雞肉串 | 180 |
        飲み物 | 飲料
        生ビール | 生啤酒 | 650 |
        菜單結束
        """)
        #expect(items.map(\.japaneseName) == ["若どり唐揚げ", "ねぎま", "生ビール"])
        #expect(items.map(\.section) == ["揚げ物", "焼き物", "飲み物"])
        #expect(items.map(\.sectionChinese) == ["炸物", "烤物", "飲料"])
    }

    @Test("兩格但看起來是菜的行不會被當成分類")
    func twoFieldItemStaysItem() {
        let items = MenuImportParser.parse("""
        分類 | 揚げ物 | 炸物
        お通し | 開胃小菜
        手羽先 | 雞翅 | 430
        """)
        #expect(items.map(\.japaneseName) == ["お通し", "手羽先"])
        #expect(items[0].section == "揚げ物")
    }

    @Test("建房代碼一律由系統產生：連建兩間代碼不同、各自都能用代碼加入，不會互相關掉")
    func generatedCodesDoNotCollide() async throws {
        let repo = InMemoryRoomRepository(currentUserId: UUID())
        let first = try await repo.createRoom(name: "第一次", hostDisplayName: "我")
        let second = try await repo.createRoom(name: "第二次", hostDisplayName: "我")
        #expect(first.room.roomCode != second.room.roomCode)
        #expect(RoomCodeGenerator.isValid(first.room.roomCode) && first.room.roomCode.count == RoomCodeGenerator.length)
        let joinedFirst = try await repo.joinRoom(code: first.room.roomCode, displayName: "媽媽")
        let joinedSecond = try await repo.joinRoom(code: second.room.roomCode, displayName: "媽媽")
        #expect(joinedFirst.room.id == first.room.id)
        #expect(joinedSecond.room.id == second.room.id)
    }
}
