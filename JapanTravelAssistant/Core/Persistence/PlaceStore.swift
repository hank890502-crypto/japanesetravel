import Foundation
import Observation

/// 旅程、地點、行程站點。存成 JSON 放在 Documents（trips.json、places.json、stops.json）。
@Observable
@MainActor
final class PlaceStore {
    private(set) var trips: [Trip] = [] { didSet { persist() } }
    private(set) var places: [Place] = [] { didSet { persist() } }
    private(set) var stops: [ItineraryStop] = [] { didSet { persist() } }

    private let directory: URL?
    private var persistTask: Task<Void, Never>?
    /// 這次 App 開著期間已經試過補座標（成功或失敗）的地點，不重試，避免被限流。
    @ObservationIgnored private var geocodeAttempted: Set<UUID> = []

    init(directory: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first) {
        self.directory = directory
        if let directory {
            trips = Self.load([Trip].self, from: directory.appendingPathComponent("trips.json")) ?? []
            places = Self.load([Place].self, from: directory.appendingPathComponent("places.json")) ?? []
            stops = Self.load([ItineraryStop].self, from: directory.appendingPathComponent("stops.json")) ?? []
        }
        migrateOrphans()
        migrateDayLabelsToStops()
    }

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// 舊版沒有旅程概念：把沒有 tripId 的地點放進「我的地點」
    private func migrateOrphans() {
        let orphans = places.filter { $0.tripId == nil }
        guard !orphans.isEmpty else { return }
        let trip = trips.first { $0.name == "我的地點" } ?? {
            let t = Trip(name: "我的地點")
            trips.append(t)
            return t
        }()
        for index in places.indices where places[index].tripId == nil {
            places[index].tripId = trip.id
        }
    }

    /// 舊版把「第幾天」存在地點上、同一地點每天存一份：改成站點，並把重複的地點合併。
    /// 只有名稱相同「而且」地址／座標沒有明顯不同的才合併；刪除前先把 places.json 備份成 places.backup.json。
    private func migrateDayLabelsToStops() {
        var didBackup = false
        for trip in trips where !stops.contains(where: { $0.tripId == trip.id }) {
            let tripPlaces = places.filter { $0.tripId == trip.id && !$0.isRecommendation }.sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
            guard !tripPlaces.isEmpty else { continue }
            var canonicalIds: [String: [UUID]] = [:]   // 鍵 → 已保留的地點（同名但不同地方可能不只一個）
            var canonical: [UUID: Place] = [:]
            var newStops: [ItineraryStop] = []
            var removed: Set<UUID> = []
            for place in tripPlaces {
                var candidates: [UUID] = []
                for key in place.dedupeKeys {
                    for id in canonicalIds[key] ?? [] where !candidates.contains(id) { candidates.append(id) }
                }
                let targetId: UUID
                if let match = candidates.first(where: { canonical[$0].map(place.looksLikeSamePlace(as:)) ?? false }) {
                    targetId = match
                    removed.insert(place.id)
                    // 被合併的那份若有保留的那份缺少的資料，補過去
                    if var kept = canonical[match], let index = places.firstIndex(where: { $0.id == match }) {
                        if kept.address?.nilIfBlank == nil { kept.address = place.address }
                        if kept.japaneseName?.nilIfBlank == nil { kept.japaneseName = place.japaneseName }
                        if kept.phone?.nilIfBlank == nil { kept.phone = place.phone }
                        if kept.note?.nilIfBlank == nil { kept.note = place.note }
                        if !kept.hasCoordinate, place.hasCoordinate { kept.latitude = place.latitude; kept.longitude = place.longitude }
                        canonical[match] = kept
                        places[index] = kept
                    }
                } else {
                    for key in place.dedupeKeys { canonicalIds[key, default: []].append(place.id) }
                    canonical[place.id] = place
                    targetId = place.id
                }
                newStops.append(ItineraryStop(tripId: trip.id, placeId: targetId, dayLabel: place.dayLabel, sortOrder: newStops.count))
            }
            stops.append(contentsOf: newStops)
            if !removed.isEmpty {
                if !didBackup { backupPlacesFile(); didBackup = true }
                places.removeAll { removed.contains($0.id) }
            }
        }
    }

    /// 遷移要刪資料前先留一份，萬一合錯還救得回來。
    private func backupPlacesFile() {
        guard let directory else { return }
        let source = directory.appendingPathComponent("places.json")
        let backup = directory.appendingPathComponent("places.backup.json")
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: source, to: backup)
    }

    // MARK: - 旅程

    var sortedTrips: [Trip] {
        trips.sorted { ($0.startDate?.date() ?? $0.createdAt) > ($1.startDate?.date() ?? $1.createdAt) }
    }

    func trip(id: UUID) -> Trip? { trips.first { $0.id == id } }

    @discardableResult
    func addTrip(name: String, startDate: DayDate? = nil, endDate: DayDate? = nil) -> Trip {
        let trip = Trip(name: name.nilIfBlank ?? "新的旅程", startDate: startDate, endDate: endDate)
        trips.append(trip)
        return trip
    }

    func updateTrip(_ trip: Trip) {
        if let index = trips.firstIndex(where: { $0.id == trip.id }) { trips[index] = trip }
    }

    /// 刪除旅程會連同裡面的地點與站點一起刪
    func removeTrip(id: UUID) {
        trips.removeAll { $0.id == id }
        places.removeAll { $0.tripId == id }
        stops.removeAll { $0.tripId == id }
    }

    // MARK: - 地點

    func place(id: UUID) -> Place? { places.first { $0.id == id } }

    /// 旅程裡「會去的地點」（不重複、不含推薦），依第一次出現在時間表的順序
    func uniquePlaces(in tripId: UUID) -> [Place] {
        var seen = Set<UUID>()
        var result: [Place] = []
        for stop in sortedStops(in: tripId) {
            guard !seen.contains(stop.placeId), let place = place(id: stop.placeId) else { continue }
            seen.insert(stop.placeId)
            result.append(place)
        }
        // 沒有站點的地點（手動新增但沒排進時間表）也算
        for place in places where place.tripId == tripId && !place.isRecommendation && !seen.contains(place.id) {
            seen.insert(place.id)
            result.append(place)
        }
        return result
    }

    /// 相容舊呼叫：旅程裡的所有地點（含推薦）
    func places(in tripId: UUID) -> [Place] {
        places.filter { $0.tripId == tripId }.sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
    }

    func recommendations(in tripId: UUID) -> [Place] {
        places.filter { $0.tripId == tripId && $0.isRecommendation }.sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
    }

    // MARK: - 時間表

    func sortedStops(in tripId: UUID) -> [ItineraryStop] {
        stops.filter { $0.tripId == tripId }.sorted { $0.sortOrder < $1.sortOrder }
    }

    struct DayGroup: Identifiable, Hashable {
        struct Entry: Identifiable, Hashable {
            var stop: ItineraryStop
            var place: Place
            var id: UUID { stop.id }
        }
        var label: String?
        var entries: [Entry]
        var id: String { label ?? "__none__" }
    }

    /// 時間表：依「第幾天」分組，順序照站點順序；沒標天數的放最後。
    func dayGroups(in tripId: UUID) -> [DayGroup] {
        var order: [String] = []
        var map: [String: [DayGroup.Entry]] = [:]
        var loose: [DayGroup.Entry] = []
        for stop in sortedStops(in: tripId) {
            guard let place = place(id: stop.placeId) else { continue }
            let entry = DayGroup.Entry(stop: stop, place: place)
            if let label = stop.dayLabel?.nilIfBlank {
                if map[label] == nil { order.append(label) }
                map[label, default: []].append(entry)
            } else {
                loose.append(entry)
            }
        }
        var groups = order.map { DayGroup(label: $0, entries: map[$0] ?? []) }
        if !loose.isEmpty { groups.append(DayGroup(label: nil, entries: loose)) }
        return groups
    }

    /// 這個地點出現在哪幾天
    func dayLabels(of placeId: UUID) -> [String] {
        var seen = Set<String>()
        return stops.filter { $0.placeId == placeId }.sorted { $0.sortOrder < $1.sortOrder }.compactMap { stop in
            guard let label = stop.dayLabel?.nilIfBlank, !seen.contains(label) else { return nil }
            seen.insert(label)
            return label
        }
    }

    // MARK: - 新增／修改

    /// 手動新增一個地點：加進旅程，並排在時間表最後（沒標天）
    func add(_ place: Place, to tripId: UUID) {
        var copy = place
        copy.tripId = tripId
        copy.sortOrder = (places(in: tripId).last?.sortOrder ?? -1) + 1
        places.append(copy)
        if !copy.isRecommendation {
            appendStop(placeId: copy.id, tripId: tripId, dayLabel: copy.dayLabel)
        }
    }

    /// 相容舊呼叫
    func addMany(_ newPlaces: [Place], to tripId: UUID) {
        for place in newPlaces { add(place, to: tripId) }
    }

    /// 匯入行程：同名地點只存一份，每次出現都是一個站點。回傳（新增的地點數、站點數、推薦數）。
    /// - 同一地點同一天已經在時間表上就不再加（同一份回覆貼兩次不會加倍）。
    /// - replaceExisting：先清掉這趟原本的時間表再匯入（地點與它們的資料保留）。
    /// - 命中既有的「推薦景點」時，它就變成會去的地點（不再是推薦）。
    @discardableResult
    func importItinerary(stops imported: [(place: Place, dayLabel: String?)], recommendations: [Place], into tripId: UUID, replaceExisting: Bool = false) -> (places: Int, stops: Int, recommendations: Int) {
        if replaceExisting {
            stops.removeAll { $0.tripId == tripId }
        }
        var byKey: [String: UUID] = [:]
        for place in places where place.tripId == tripId {
            for key in place.dedupeKeys where byKey[key] == nil { byKey[key] = place.id }
        }
        func existingId(for place: Place) -> UUID? {
            place.dedupeKeys.lazy.compactMap { byKey[$0] }.first
        }
        func register(_ place: Place) {
            for key in place.dedupeKeys where byKey[key] == nil { byKey[key] = place.id }
        }

        var addedPlaces = 0
        var addedStops = 0
        var nextSort = (places(in: tripId).last?.sortOrder ?? -1) + 1
        for entry in imported {
            var place = entry.place
            place.tripId = tripId
            place.isRecommendation = false
            let placeId: UUID
            if let existing = existingId(for: place) {
                placeId = existing
                if let index = places.firstIndex(where: { $0.id == existing }) {
                    // 補上原本沒有的資料
                    if places[index].address?.nilIfBlank == nil { places[index].address = place.address }
                    if places[index].japaneseName?.nilIfBlank == nil { places[index].japaneseName = place.japaneseName }
                    if places[index].note?.nilIfBlank == nil { places[index].note = place.note }
                    // 原本只是推薦、現在排進行程了
                    if places[index].isRecommendation {
                        places[index].isRecommendation = false
                        places[index].recommendationReason = nil
                    }
                    register(places[index])
                }
            } else {
                place.sortOrder = nextSort
                nextSort += 1
                places.append(place)
                register(place)
                placeId = place.id
                addedPlaces += 1
            }
            let alreadyScheduled = stops.contains { $0.tripId == tripId && $0.placeId == placeId && $0.dayLabel?.nilIfBlank == entry.dayLabel?.nilIfBlank }
            if !alreadyScheduled {
                appendStop(placeId: placeId, tripId: tripId, dayLabel: entry.dayLabel)
                addedStops += 1
            }
        }
        var addedRecommendations = 0
        for var rec in recommendations {
            rec.tripId = tripId
            rec.isRecommendation = true
            guard existingId(for: rec) == nil else { continue }
            rec.sortOrder = nextSort
            nextSort += 1
            places.append(rec)
            register(rec)
            addedRecommendations += 1
        }
        return (addedPlaces, addedStops, addedRecommendations)
    }

    private func appendStop(placeId: UUID, tripId: UUID, dayLabel: String?) {
        let next = (sortedStops(in: tripId).last?.sortOrder ?? -1) + 1
        stops.append(ItineraryStop(tripId: tripId, placeId: placeId, dayLabel: dayLabel?.nilIfBlank, sortOrder: next))
    }

    func update(_ place: Place) {
        if let index = places.firstIndex(where: { $0.id == place.id }) { places[index] = place }
    }

    /// 修改「第幾天」：套用到這個地點的第一個站點（沒有就建一個）
    func setDayLabel(_ label: String?, for placeId: UUID) {
        if let index = stops.firstIndex(where: { $0.placeId == placeId }) {
            stops[index].dayLabel = label?.nilIfBlank
        } else if let place = place(id: placeId), let tripId = place.tripId {
            appendStop(placeId: placeId, tripId: tripId, dayLabel: label?.nilIfBlank)
        }
    }

    /// 推薦景點加進行程（變成一般地點，並排在時間表最後）。已經在行程裡的不會重複加。
    func addRecommendationToItinerary(placeId: UUID) {
        guard let index = places.firstIndex(where: { $0.id == placeId }), let tripId = places[index].tripId,
              places[index].isRecommendation else { return }
        places[index].isRecommendation = false
        appendStop(placeId: placeId, tripId: tripId, dayLabel: nil)
    }

    /// 刪地點：連同它在時間表上的所有站點
    func remove(id: UUID) {
        places.removeAll { $0.id == id }
        stops.removeAll { $0.placeId == id }
    }

    /// 只刪時間表上的一站，地點本身保留（它在其他天的站點也保留）。
    func removeStop(id: UUID) {
        stops.removeAll { $0.id == id }
    }

    // MARK: - 補座標

    /// 背景補座標用：只有還沒有座標的才更新
    func setCoordinate(placeId: UUID, latitude: Double, longitude: Double, address: String? = nil) {
        guard let index = places.firstIndex(where: { $0.id == placeId }), !places[index].hasCoordinate else { return }
        places[index].latitude = latitude
        places[index].longitude = longitude
        if places[index].address?.nilIfBlank == nil, let address { places[index].address = address }
    }

    /// 這趟裡還沒有座標、有地址或日文名可以查、而且這次 App 開著期間還沒試過的地點。
    func placesNeedingGeocode(in tripId: UUID) -> [Place] {
        places(in: tripId).filter {
            !$0.hasCoordinate && !geocodeAttempted.contains($0.id) && ($0.address?.nilIfBlank != nil || $0.japaneseName?.nilIfBlank != nil)
        }
    }

    /// 記下這個地點已經查過座標（不論成功失敗），這次不再重試。
    func markGeocodeAttempted(_ placeId: UUID) {
        geocodeAttempted.insert(placeId)
    }

    // MARK: - 分享（匯出／匯入整趟）

    func package(for tripId: UUID) -> TripPackage? {
        guard let trip = trip(id: tripId) else { return nil }
        return TripPackage(trip: trip, places: places.filter { $0.tripId == tripId }, stops: sortedStops(in: tripId))
    }

    /// 收到別人分享的旅程：同一趟（相同 id）就整份更新，否則新增一趟。
    @discardableResult
    func importPackage(_ package: TripPackage) -> Trip {
        var trip = package.trip
        if trips.contains(where: { $0.id == trip.id }) {
            places.removeAll { $0.tripId == trip.id }
            stops.removeAll { $0.tripId == trip.id }
            updateTrip(trip)
        } else {
            trip.createdAt = .now
            trips.append(trip)
        }
        places.append(contentsOf: package.places.map { var p = $0; p.tripId = trip.id; return p })
        stops.append(contentsOf: package.stops.map { var s = $0; s.tripId = trip.id; return s })
        return trip
    }

    // MARK: - Persistence

    private func persist() {
        guard let directory else { return }
        let tripsSnapshot = trips, placesSnapshot = places, stopsSnapshot = stops
        persistTask?.cancel()
        persistTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(tripsSnapshot) { try? data.write(to: directory.appendingPathComponent("trips.json"), options: .atomic) }
            if let data = try? JSONEncoder().encode(placesSnapshot) { try? data.write(to: directory.appendingPathComponent("places.json"), options: .atomic) }
            if let data = try? JSONEncoder().encode(stopsSnapshot) { try? data.write(to: directory.appendingPathComponent("stops.json"), options: .atomic) }
        }
    }
}
