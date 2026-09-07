import Foundation
import Observation

/// 旅程與地點。存成 JSON 放在 Documents（trips.json、places.json）。
@Observable
@MainActor
final class PlaceStore {
    private(set) var trips: [Trip] = [] { didSet { persist() } }
    private(set) var places: [Place] = [] { didSet { persist() } }

    private let directory: URL?
    private var persistTask: Task<Void, Never>?

    init(directory: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first) {
        self.directory = directory
        if let directory {
            if let data = try? Data(contentsOf: directory.appendingPathComponent("trips.json")), let decoded = try? JSONDecoder().decode([Trip].self, from: data) {
                trips = decoded
            }
            if let data = try? Data(contentsOf: directory.appendingPathComponent("places.json")), let decoded = try? JSONDecoder().decode([Place].self, from: data) {
                places = decoded
            }
        }
        migrateOrphans()
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

    // MARK: - 旅程

    var sortedTrips: [Trip] {
        trips.sorted { ($0.startDate ?? $0.createdAt) > ($1.startDate ?? $1.createdAt) }
    }

    func trip(id: UUID) -> Trip? { trips.first { $0.id == id } }

    @discardableResult
    func addTrip(name: String, startDate: Date? = nil, endDate: Date? = nil) -> Trip {
        let trip = Trip(name: name.nilIfBlank ?? "新的旅程", startDate: startDate, endDate: endDate)
        trips.append(trip)
        return trip
    }

    func updateTrip(_ trip: Trip) {
        if let index = trips.firstIndex(where: { $0.id == trip.id }) { trips[index] = trip }
    }

    /// 刪除旅程會連同裡面的地點一起刪
    func removeTrip(id: UUID) {
        trips.removeAll { $0.id == id }
        places.removeAll { $0.tripId == id }
    }

    // MARK: - 地點

    func place(id: UUID) -> Place? { places.first { $0.id == id } }

    func places(in tripId: UUID) -> [Place] {
        places.filter { $0.tripId == tripId }.sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
    }

    struct DayGroup: Identifiable, Hashable {
        var label: String?
        var places: [Place]
        var id: String { label ?? "__none__" }
    }

    /// 依「第幾天」分組，順序照出現順序；沒有標天數的放最後。
    func dayGroups(in tripId: UUID) -> [DayGroup] {
        let list = places(in: tripId)
        var order: [String] = []
        var map: [String: [Place]] = [:]
        var loose: [Place] = []
        for place in list {
            if let label = place.dayLabel?.nilIfBlank {
                if map[label] == nil { order.append(label) }
                map[label, default: []].append(place)
            } else {
                loose.append(place)
            }
        }
        var groups = order.map { DayGroup(label: $0, places: map[$0] ?? []) }
        if !loose.isEmpty { groups.append(DayGroup(label: nil, places: loose)) }
        return groups
    }

    /// 加到旅程最後面
    func add(_ place: Place, to tripId: UUID) {
        var copy = place
        copy.tripId = tripId
        copy.sortOrder = (places(in: tripId).last?.sortOrder ?? -1) + 1
        places.append(copy)
    }

    func addMany(_ newPlaces: [Place], to tripId: UUID) {
        var next = (places(in: tripId).last?.sortOrder ?? -1) + 1
        var batch: [Place] = []
        for place in newPlaces {
            var copy = place
            copy.tripId = tripId
            copy.sortOrder = next
            next += 1
            batch.append(copy)
        }
        places.append(contentsOf: batch)
    }

    func update(_ place: Place) {
        if let index = places.firstIndex(where: { $0.id == place.id }) { places[index] = place }
    }

    func remove(id: UUID) {
        places.removeAll { $0.id == id }
    }

    /// 背景補座標用：只有還沒有座標的才更新
    func setCoordinate(placeId: UUID, latitude: Double, longitude: Double, address: String? = nil) {
        guard let index = places.firstIndex(where: { $0.id == placeId }), !places[index].hasCoordinate else { return }
        places[index].latitude = latitude
        places[index].longitude = longitude
        if places[index].address?.nilIfBlank == nil, let address { places[index].address = address }
    }

    // MARK: - Persistence

    private func persist() {
        guard let directory else { return }
        let tripsSnapshot = trips, placesSnapshot = places
        persistTask?.cancel()
        persistTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(tripsSnapshot) { try? data.write(to: directory.appendingPathComponent("trips.json"), options: .atomic) }
            if let data = try? JSONEncoder().encode(placesSnapshot) { try? data.write(to: directory.appendingPathComponent("places.json"), options: .atomic) }
        }
    }
}
