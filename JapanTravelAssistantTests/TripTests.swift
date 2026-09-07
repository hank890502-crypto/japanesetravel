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

    @Test("解析：表頭行（地點 | 中文名稱 | 日文正式名稱 | …）不會變成地點")
    func parseSkipsHeaderRows() {
        let text = """
        | 地點 | 中文名稱 | 日文正式名稱 | 日文地址（含郵遞區號） | 類型 | 一句備註 |
        |---|---|---|---|---|---|
        地點 | 日文名稱 | 地址 | 類型 | 備註
        | 中文名稱 | 日文 | 地址 | 類型 |
        推薦 | 中文名稱 | 日文正式名稱 | 日文地址 | 類型 | 為什麼推薦
        天 | 第1天 | 2026-09-12 | 名古屋
        地點 | 名古屋城 | 名古屋城 | 〒460-0031 愛知県名古屋市中区本丸1-1 | 景點 | 9:00–16:30
        推薦 | 大須商店街 | 大須商店街 | 愛知県名古屋市中区大須3丁目 | 商店 | 好逛
        """
        let result = TripImportParser.parse(text)
        #expect(result.places.map(\.name) == ["名古屋城", "大須商店街"])
        #expect(result.itinerary.count == 1 && result.recommendations.count == 1)
        #expect(result.places[0].address == "〒460-0031 愛知県名古屋市中区本丸1-1")
    }

    @Test("解析：只貼了格式範本（沒有真的行程）→ 沒有地點、沒有旅程名")
    func parseTemplateOnlyYieldsNothing() {
        let result = TripImportParser.parse(ChatGPTTripPrompt.text)
        #expect(result.places.isEmpty)
        #expect(result.tripName == nil)
    }

    @Test("解析：提示文字和回覆一起貼進來，取最後一個「行程開始」之後的真行程")
    func parseUsesLastStartMarker() {
        let text = ChatGPTTripPrompt.text + """

        好的，整理如下：
        行程開始
        行程 | 9月名古屋 | 2026-09-12 | 2026-09-16
        天 | 第1天 | 2026-09-12 | 名古屋
        地點 | 名古屋城 | 名古屋城 | 愛知県名古屋市中区本丸1-1 | 景點 |
        行程結束
        """
        let result = TripImportParser.parse(text)
        #expect(result.tripName == "9月名古屋")
        #expect(result.places.map(\.name) == ["名古屋城"])
        #expect(result.startDate == DayDate(year: 2026, month: 9, day: 12))
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

    @Test("匯入同一份行程兩次：站點不會加倍；「取代」會換掉時間表但保留地點")
    @MainActor
    func importTwiceDoesNotDuplicateStops() {
        let store = PlaceStore(directory: nil)
        let trip = store.addTrip(name: "測試")
        let stops: [(place: Place, dayLabel: String?)] = [
            (Place(name: "名古屋車站", category: .station, japaneseName: "名古屋駅"), "第1天"),
            (Place(name: "我們的飯店", category: .hotel, japaneseName: "ドーミーイン名古屋"), "第1天"),
            (Place(name: "我們的飯店", category: .hotel, japaneseName: "ドーミーイン名古屋"), "第2天"),
        ]
        let first = store.importItinerary(stops: stops, recommendations: [], into: trip.id)
        #expect(first.places == 2 && first.stops == 3)

        let second = store.importItinerary(stops: stops, recommendations: [], into: trip.id)
        #expect(second.places == 0 && second.stops == 0)
        #expect(store.sortedStops(in: trip.id).count == 3)
        #expect(store.dayGroups(in: trip.id).map { $0.entries.count } == [2, 1])

        // 微調後重貼、選「取代」：時間表換成新的，地點（含原本的資料）保留
        var hotel = store.uniquePlaces(in: trip.id)[1]
        hotel.phone = "+81-52-000-0000"
        store.update(hotel)
        let replaced = store.importItinerary(stops: [
            (Place(name: "我們的飯店", category: .hotel, japaneseName: "ドーミーイン名古屋"), "第1天"),
            (Place(name: "名古屋城", category: .sight, japaneseName: "名古屋城"), "第2天"),
        ], recommendations: [], into: trip.id, replaceExisting: true)
        #expect(replaced.places == 1 && replaced.stops == 2)
        #expect(store.sortedStops(in: trip.id).count == 2)
        #expect(store.place(id: hotel.id)?.phone == "+81-52-000-0000")
        #expect(store.uniquePlaces(in: trip.id).map(\.name) == ["我們的飯店", "名古屋城", "名古屋車站"])   // 車站沒站點了，但地點還在

        // 只刪時間表上的一站，地點保留
        let stop = store.sortedStops(in: trip.id)[0]
        store.removeStop(id: stop.id)
        #expect(store.sortedStops(in: trip.id).count == 1)
        #expect(store.place(id: stop.placeId) != nil)
    }

    @Test("匯入命中既有的推薦景點：它變成會去的地點，不再同時是推薦；重複加到行程不會多站點")
    @MainActor
    func importPromotesRecommendation() {
        let store = PlaceStore(directory: nil)
        let trip = store.addTrip(name: "測試")
        store.importItinerary(stops: [
            (Place(name: "名古屋城", category: .sight, japaneseName: "名古屋城"), "第1天"),
        ], recommendations: [
            Place(name: "大須商店街", category: .shopping, japaneseName: "大須商店街", recommendationReason: "好逛"),
        ], into: trip.id)
        let osu = store.recommendations(in: trip.id)[0]

        // 回 ChatGPT 說「把大須排進第 2 天」再匯入一次
        let summary = store.importItinerary(stops: [
            (Place(name: "名古屋城", category: .sight, japaneseName: "名古屋城"), "第1天"),
            (Place(name: "大須商店街", category: .shopping, japaneseName: "大須商店街"), "第2天"),
        ], recommendations: [], into: trip.id)
        #expect(summary.places == 0 && summary.stops == 1)
        #expect(store.recommendations(in: trip.id).isEmpty)
        #expect(store.place(id: osu.id)?.isRecommendation == false)
        #expect(store.place(id: osu.id)?.recommendationReason == nil)
        #expect(store.uniquePlaces(in: trip.id).map(\.id) == [store.uniquePlaces(in: trip.id)[0].id, osu.id])
        #expect(Set(store.uniquePlaces(in: trip.id).map(\.id)).count == store.uniquePlaces(in: trip.id).count)

        // 已經在行程裡的再按「加到這趟行程」不會多一個站點
        let before = store.sortedStops(in: trip.id).count
        store.addRecommendationToItinerary(placeId: osu.id)
        #expect(store.sortedStops(in: trip.id).count == before)
    }

    @Test("合併鍵對稱：有日文名與沒日文名的同一個地方會合併")
    @MainActor
    func dedupeIsSymmetric() {
        let store = PlaceStore(directory: nil)
        let trip = store.addTrip(name: "測試")
        store.importItinerary(stops: [
            (Place(name: "我們的飯店", category: .hotel, japaneseName: "ドーミーイン名古屋"), "第1天"),
        ], recommendations: [], into: trip.id)
        // 補充匯入時 ChatGPT 只給中文名
        let summary = store.importItinerary(stops: [
            (Place(name: "我們的飯店", category: .hotel, japaneseName: nil), "第2天"),
        ], recommendations: [], into: trip.id)
        #expect(summary.places == 0 && summary.stops == 1)
        #expect(store.uniquePlaces(in: trip.id).count == 1)
        #expect(store.dayLabels(of: store.uniquePlaces(in: trip.id)[0].id) == ["第1天", "第2天"])

        // 反過來：先存的沒有日文名（手動新增），後來匯入的有 → 也合併，並補上日文名
        let trip2 = store.addTrip(name: "測試2")
        store.add(Place(name: "名古屋城", category: .sight), to: trip2.id)
        let summary2 = store.importItinerary(stops: [
            (Place(name: "名古屋城", category: .sight, japaneseName: "名古屋城（本丸）"), "第1天"),
        ], recommendations: [], into: trip2.id)
        #expect(summary2.places == 0)
        #expect(store.uniquePlaces(in: trip2.id).count == 1)
        #expect(store.uniquePlaces(in: trip2.id)[0].japaneseName == "名古屋城（本丸）")
        #expect(Place(name: "飯店", japaneseName: "ホテル").dedupeKeys == ["ホテル", "飯店"])
    }

    @Test("背景補座標：只列還沒試過的；試過（不論成敗）就不再列")
    @MainActor
    func geocodeQueueSkipsAttempted() {
        let store = PlaceStore(directory: nil)
        let trip = store.addTrip(name: "測試")
        let withAddress = Place(name: "A", address: "愛知県名古屋市中区本丸1-1", category: .sight)
        let withJapanese = Place(name: "B", category: .sight, japaneseName: "名古屋駅")
        let nothing = Place(name: "C", category: .other)
        let located = Place(name: "D", latitude: 35, longitude: 136, category: .other)
        store.addMany([withAddress, withJapanese, nothing, located], to: trip.id)
        #expect(store.placesNeedingGeocode(in: trip.id).map(\.name) == ["A", "B"])

        store.markGeocodeAttempted(withAddress.id)   // 查失敗
        #expect(store.placesNeedingGeocode(in: trip.id).map(\.name) == ["B"])
        store.markGeocodeAttempted(withJapanese.id)
        store.setCoordinate(placeId: withJapanese.id, latitude: 35.1, longitude: 136.9)
        #expect(store.placesNeedingGeocode(in: trip.id).isEmpty)
    }

    @Test("舊資料：同名但地址不同的兩家「晚餐」不會被合併，而且合併前會備份 places.json")
    @MainActor
    func migrationKeepsDistinctPlaces() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TripTests-distinct-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let trip = Trip(name: "舊行程")
        let legacy = [
            Place(name: "晚餐", address: "愛知県名古屋市中区栄3丁目", category: .restaurant, phone: "052-111", tripId: trip.id, dayLabel: "第1天", sortOrder: 0),
            Place(name: "晚餐", address: "愛知県名古屋市中村区名駅1丁目", category: .restaurant, phone: "052-222", tripId: trip.id, dayLabel: "第2天", sortOrder: 1),
            Place(name: "飯店", address: "〒460-0008 愛知県名古屋市中区栄3丁目", category: .hotel, tripId: trip.id, dayLabel: "第1天", sortOrder: 2),
            Place(name: "飯店", category: .hotel, tripId: trip.id, dayLabel: "第2天", sortOrder: 3),   // 沒地址 → 可以跟上面那家合併
        ]
        try JSONEncoder().encode([trip]).write(to: dir.appendingPathComponent("trips.json"))
        try JSONEncoder().encode(legacy).write(to: dir.appendingPathComponent("places.json"))
        let store = PlaceStore(directory: dir)
        let unique = store.uniquePlaces(in: trip.id)
        #expect(unique.map(\.name) == ["晚餐", "晚餐", "飯店"])
        #expect(Set(unique.compactMap(\.phone)) == ["052-111", "052-222"])
        #expect(store.sortedStops(in: trip.id).count == 4)
        let day2 = store.dayGroups(in: trip.id).first { $0.label == "第2天" }
        #expect(day2?.entries.first?.place.phone == "052-222")
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("places.backup.json").path))
        let backup = try JSONDecoder().decode([Place].self, from: Data(contentsOf: dir.appendingPathComponent("places.backup.json")))
        #expect(backup.count == 4)
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

@Suite("旅程日期（只存哪一天）")
struct DayDateTests {
    @Test("ChatGPT 的日期解析成年月日，跟手機時區無關；顯示成 9/12 – 9/16")
    func parseAndDisplay() {
        #expect(TripImportParser.parseDate("2026-09-12") == DayDate(year: 2026, month: 9, day: 12))
        #expect(TripImportParser.parseDate("2026/9/2") == DayDate(year: 2026, month: 9, day: 2))
        #expect(TripImportParser.parseDate("2026年9月12日") == DayDate(year: 2026, month: 9, day: 12))
        #expect(TripImportParser.parseDate("不確定") == nil)
        let trip = Trip(name: "測試", startDate: DayDate(year: 2026, month: 9, day: 12), endDate: DayDate(year: 2026, month: 9, day: 16))
        #expect(trip.dateRangeText == "9/12 – 9/16")
        #expect(Trip(name: "一天", startDate: DayDate(year: 2026, month: 9, day: 12), endDate: DayDate(year: 2026, month: 9, day: 12)).dateRangeText == "9/12")
        #expect(Trip(name: "沒日期").dateRangeText == nil)
    }

    @Test("存成 yyyy-MM-dd 字串；舊資料（Date）與 ISO 字串也讀得懂")
    func codableCompatibility() throws {
        let day = DayDate(year: 2026, month: 9, day: 12)
        let encoded = try JSONEncoder().encode(day)
        #expect(String(decoding: encoded, as: UTF8.self) == "\"2026-09-12\"")
        #expect(try JSONDecoder().decode(DayDate.self, from: encoded) == day)

        // 舊版：當地午夜的 Date（JSONEncoder 預設存成秒數）
        let legacyDate = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 12))!
        let legacyJSON = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"舊旅程","startDate":\#(legacyDate.timeIntervalSinceReferenceDate),"createdAt":0}"#
        let trip = try JSONDecoder().decode(Trip.self, from: Data(legacyJSON.utf8))
        #expect(trip.startDate == day)
        #expect(trip.endDate == nil)

        // 含時間的字串（例如別的工具產生）：取日期部分
        #expect(try JSONDecoder().decode(DayDate.self, from: Data("\"2026-09-12T15:00:00Z\"".utf8)) == day)

        // 看不懂的日期不會讓整趟旅程讀不進來
        let weird = try JSONDecoder().decode(Trip.self, from: Data(#"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"x","startDate":"someday"}"#.utf8))
        #expect(weird.startDate == nil && weird.name == "x")
    }

    @Test("旅程檔分享：日期是年月日，收件人在不同時區看到的還是同一天")
    @MainActor
    func packageKeepsDay() throws {
        let sender = PlaceStore(directory: nil)
        let trip = sender.addTrip(name: "9 月名古屋", startDate: DayDate(year: 2026, month: 9, day: 12), endDate: DayDate(year: 2026, month: 9, day: 16))
        sender.add(Place(name: "名古屋城", category: .sight), to: trip.id)
        let data = try #require(sender.package(for: trip.id)).encoded()
        #expect(String(decoding: data, as: UTF8.self).contains("\"startDate\" : \"2026-09-12\""))
        let decoded = try TripPackage.decode(data)
        #expect(decoded.trip.dateRangeText == "9/12 – 9/16")
    }
}

@Suite("旅程分享")
struct TripShareTests {
    @Test("旅程檔：新版 App 的版本 → 提示更新；壞掉的檔案 → 白話錯誤；不認識的類型退回其他")
    func decodeFailuresAreUserFacing() throws {
        let tooNew = Data(#"{"version":99,"trip":{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"x"},"places":[],"stops":[]}"#.utf8)
        #expect(throws: UserFacingError.self) { try TripPackage.decode(tooNew) }
        do {
            _ = try TripPackage.decode(tooNew)
        } catch let error as UserFacingError {
            #expect(error.title.contains("新版"))
        }

        do {
            _ = try TripPackage.decode(Data("這不是旅程檔".utf8))
            Issue.record("應該要失敗")
        } catch let error as UserFacingError {
            #expect(error == .unreadableTripFile)
        }

        let unknownCategory = Data(#"""
        {"version":1,"trip":{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"x"},
         "places":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964F0","name":"溫泉","category":"onsen"}],
         "stops":[]}
        """#.utf8)
        let package = try TripPackage.decode(unknownCategory)
        #expect(package.places.first?.category == .other)
        #expect(package.places.first?.name == "溫泉")
    }

    @Test("匯出成檔案再匯入：新裝置新增一趟，同一趟則更新")
    @MainActor
    func roundTrip() throws {
        let sender = PlaceStore(directory: nil)
        let trip = sender.addTrip(name: "9 月名古屋", startDate: .today)
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
