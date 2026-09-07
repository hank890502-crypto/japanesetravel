import Foundation
import Testing
@testable import JapanTravelAssistant

@Suite("旅程")
struct TripTests {
    @Test("ChatGPT 行程格式：旅程、天、地點，含沒有標記的行與粗體")
    func parseTrip() {
        let text = """
        行程開始
        行程 | 9月名古屋親子遊 | 2026-09-12 | 2026-09-16
        天 | 第1天 | 2026-09-12 | 名古屋
        地點 | 我們的飯店 | ドーミーイン名古屋栄 | 〒460-0008 愛知県名古屋市中区栄3丁目 | 飯店 | 退房 11:00
        **地點 | 名古屋車站 | 名古屋駅 | 〒450-0002 愛知県名古屋市中村区名駅1丁目 | 車站 | **
        天 | 第2天 | 2026-09-13 | 犬山
        - 地點 | 犬山城 | 犬山城 | 愛知県犬山市犬山北古券65-2 | 景點 | 9:00–17:00
        行程結束
        """
        let result = TripImportParser.parse(text)
        #expect(result.tripName == "9月名古屋親子遊")
        #expect(result.startDate != nil && result.endDate != nil)
        #expect(result.places.map(\.name) == ["我們的飯店", "名古屋車站", "犬山城"])
        #expect(result.places.map(\.category) == [.hotel, .station, .sight])
        #expect(result.places[0].dayLabel == "第1天 9/12 名古屋")
        #expect(result.places[2].dayLabel == "第2天 9/13 犬山")
        #expect(result.places[0].japaneseName == "ドーミーイン名古屋栄")
        #expect(result.places[0].note == "退房 11:00")
        #expect(result.places[1].note == nil)
    }

    @Test("類型文字寬容：旅館→飯店、機場→車站、居酒屋→餐廳")
    func categoryMapping() {
        #expect(TripImportParser.category(from: "旅館") == .hotel)
        #expect(TripImportParser.category(from: "機場") == .station)
        #expect(TripImportParser.category(from: "居酒屋") == .restaurant)
        #expect(TripImportParser.category(from: "藥妝店") == .shopping)
        #expect(TripImportParser.category(from: "神社") == .sight)
        #expect(TripImportParser.category(from: "??") == .other)
    }

    @Test("旅程與地點：分天、順序、刪旅程連帶刪地點、舊地點自動歸到「我的地點」")
    @MainActor
    func storeTrips() {
        let store = PlaceStore(directory: nil)
        let trip = store.addTrip(name: "9 月名古屋")
        store.addMany([
            Place(name: "飯店", category: .hotel, dayLabel: "第1天"),
            Place(name: "車站", category: .station, dayLabel: "第1天"),
            Place(name: "城", category: .sight, dayLabel: "第2天"),
            Place(name: "沒標天", category: .other),
        ], to: trip.id)
        let groups = store.dayGroups(in: trip.id)
        #expect(groups.map(\.label) == ["第1天", "第2天", nil])
        #expect(groups[0].places.map(\.name) == ["飯店", "車站"])
        #expect(store.places(in: trip.id).map(\.sortOrder) == [0, 1, 2, 3])

        store.add(Place(name: "新的", category: .other), to: trip.id)
        #expect(store.places(in: trip.id).last?.name == "新的")

        store.setCoordinate(placeId: store.places(in: trip.id)[0].id, latitude: 35, longitude: 136)
        #expect(store.places(in: trip.id)[0].hasCoordinate)

        store.removeTrip(id: trip.id)
        #expect(store.trips.isEmpty && store.places.isEmpty)
    }

    @Test("舊版沒有旅程的地點會被搬進「我的地點」")
    @MainActor
    func migration() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TripTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let legacy = [Place(name: "東京駅", category: .station)]
        try JSONEncoder().encode(legacy).write(to: dir.appendingPathComponent("places.json"))
        let store = PlaceStore(directory: dir)
        #expect(store.trips.count == 1 && store.trips.first?.name == "我的地點")
        #expect(store.places.first?.tripId == store.trips.first?.id)
    }
}
