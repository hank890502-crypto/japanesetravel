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

    @Test("旅程與地點：分天、順序、刪旅程連帶刪地點與站點")
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
        #expect(groups[0].entries.map(\.place.name) == ["飯店", "車站"])
        #expect(store.uniquePlaces(in: trip.id).count == 4)

        store.setCoordinate(placeId: store.places(in: trip.id)[0].id, latitude: 35, longitude: 136)
        #expect(store.places(in: trip.id)[0].hasCoordinate)

        store.removeTrip(id: trip.id)
        #expect(store.trips.isEmpty && store.places.isEmpty && store.stops.isEmpty)
    }

    @Test("匯入：同名地點只存一份但時間表每天都有；推薦另外放；推薦可加到行程")
    @MainActor
    func importDedupes() {
        let store = PlaceStore(directory: nil)
        let trip = store.addTrip(name: "測試")
        let hotel = Place(name: "我們的飯店", category: .hotel, japaneseName: "ドーミーイン名古屋")
        let summary = store.importItinerary(stops: [
            (Place(name: "名古屋車站", category: .station, japaneseName: "名古屋駅"), "第1天"),
            (hotel, "第1天"),
            (Place(name: "名古屋城", category: .sight, japaneseName: "名古屋城"), "第2天"),
            (Place(name: "飯店", category: .hotel, japaneseName: "ドーミーイン 名古屋"), "第2天"),   // 同一間飯店，寫法略不同
        ], recommendations: [
            Place(name: "大須商店街", category: .shopping, japaneseName: "大須商店街", recommendationReason: "好逛"),
            Place(name: "名古屋城", category: .sight, japaneseName: "名古屋城"),   // 已在行程裡 → 不重複加
        ], into: trip.id)
        #expect(summary.places == 3 && summary.stops == 4 && summary.recommendations == 1)
        #expect(store.uniquePlaces(in: trip.id).map(\.name) == ["名古屋車站", "我們的飯店", "名古屋城"])
        #expect(store.dayGroups(in: trip.id).map { $0.entries.count } == [2, 2])
        #expect(store.dayLabels(of: store.uniquePlaces(in: trip.id)[1].id) == ["第1天", "第2天"])
        #expect(store.recommendations(in: trip.id).map(\.name) == ["大須商店街"])

        store.addRecommendationToItinerary(placeId: store.recommendations(in: trip.id)[0].id)
        #expect(store.recommendations(in: trip.id).isEmpty)
        #expect(store.uniquePlaces(in: trip.id).count == 4)
    }

    @Test("解析：推薦行與去的行分開")
    func parseRecommendations() {
        let result = TripImportParser.parse("""
        天 | 第1天 | 2026-09-12 | 名古屋
        地點 | 名古屋城 | 名古屋城 | 愛知県名古屋市中区本丸1-1 | 景點 |
        推薦 | 大須商店街 | 大須商店街 | 愛知県名古屋市中区大須3丁目 | 商店 | 好逛好吃
        """)
        #expect(result.itinerary.map(\.name) == ["名古屋城"])
        #expect(result.recommendations.map(\.name) == ["大須商店街"])
        #expect(result.recommendations[0].note == "好逛好吃")
        #expect(result.recommendations[0].dayLabel == nil)
    }

    @Test("舊資料：同一地點每天各存一份 → 合併成一份 + 多個站點")
    @MainActor
    func migrateDuplicates() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TripTests-dup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let trip = Trip(name: "舊行程")
        let legacy = [
            Place(name: "飯店", category: .hotel, tripId: trip.id, japaneseName: "ホテル", dayLabel: "第1天", sortOrder: 0),
            Place(name: "城", category: .sight, tripId: trip.id, dayLabel: "第1天", sortOrder: 1),
            Place(name: "飯店", category: .hotel, tripId: trip.id, japaneseName: "ホテル", dayLabel: "第2天", sortOrder: 2),
        ]
        try JSONEncoder().encode([trip]).write(to: dir.appendingPathComponent("trips.json"))
        try JSONEncoder().encode(legacy).write(to: dir.appendingPathComponent("places.json"))
        let store = PlaceStore(directory: dir)
        #expect(store.uniquePlaces(in: trip.id).map(\.name) == ["飯店", "城"])
        #expect(store.sortedStops(in: trip.id).count == 3)
        #expect(store.dayGroups(in: trip.id).map(\.label) == ["第1天", "第2天"])
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

@Suite("旅程分享")
struct TripShareTests {
    @Test("匯出成檔案再匯入：新裝置新增一趟，同一趟則更新")
    @MainActor
    func roundTrip() throws {
        let sender = PlaceStore(directory: nil)
        let trip = sender.addTrip(name: "9 月名古屋", startDate: .now)
        sender.importItinerary(stops: [
            (Place(name: "名古屋城", category: .sight, japaneseName: "名古屋城"), "第1天"),
            (Place(name: "飯店", category: .hotel, japaneseName: "ホテル"), "第1天"),
        ], recommendations: [Place(name: "大須商店街", category: .shopping, recommendationReason: "好逛")], into: trip.id)
        let package = try #require(sender.package(for: trip.id))
        let data = try package.encoded()
        #expect(package.fileName == "9 月名古屋.jptrip")

        let receiver = PlaceStore(directory: nil)
        let decoded = try TripPackage.decode(data)
        let imported = receiver.importPackage(decoded)
        #expect(receiver.trips.count == 1 && imported.id == trip.id)
        #expect(receiver.uniquePlaces(in: trip.id).map(\.name) == ["名古屋城", "飯店"])
        #expect(receiver.recommendations(in: trip.id).count == 1)
        #expect(receiver.dayGroups(in: trip.id).first?.entries.count == 2)

        // 寄件人再加一個地點、再分享一次 → 收件人更新，不會重複
        sender.add(Place(name: "熱田神宮", category: .sight), to: trip.id)
        receiver.importPackage(try #require(sender.package(for: trip.id)))
        #expect(receiver.trips.count == 1)
        #expect(receiver.uniquePlaces(in: trip.id).count == 3)
    }
}
