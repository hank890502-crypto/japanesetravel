import Foundation
import Observation

/// 使用者儲存的地點。存成 JSON 放在 Documents。
@Observable
@MainActor
final class PlaceStore {
    private(set) var places: [Place] = [] {
        didSet { persist() }
    }

    private let fileURL: URL?
    private var persistTask: Task<Void, Never>?

    init(directory: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first) {
        fileURL = directory?.appendingPathComponent("places.json")
        if let fileURL, let data = try? Data(contentsOf: fileURL), let decoded = try? JSONDecoder().decode([Place].self, from: data) {
            places = decoded
        }
    }

    func place(id: UUID) -> Place? { places.first { $0.id == id } }

    func add(_ place: Place) {
        places.insert(place, at: 0)
    }

    func update(_ place: Place) {
        if let index = places.firstIndex(where: { $0.id == place.id }) {
            places[index] = place
        } else {
            places.insert(place, at: 0)
        }
    }

    func remove(id: UUID) {
        places.removeAll { $0.id == id }
    }

    /// 把最近用過的移到最前面（列表順序 = 最近使用）
    func markUsed(id: UUID) {
        guard let index = places.firstIndex(where: { $0.id == id }), index != 0 else { return }
        let place = places.remove(at: index)
        places.insert(place, at: 0)
    }

    private func persist() {
        guard let fileURL else { return }
        let snapshot = places
        persistTask?.cancel()
        persistTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }
}
