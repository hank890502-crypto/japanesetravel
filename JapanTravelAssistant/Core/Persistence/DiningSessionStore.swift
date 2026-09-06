import Foundation
import Observation

/// 這台手機目前所在的用餐房間。存在 UserDefaults，App 重開後可以直接回到房間。
@Observable
@MainActor
final class DiningSessionStore {
    var current: RoomSession? {
        didSet { persist() }
    }

    private let defaults: UserDefaults
    private let key = "currentRoomSession"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let session = try? JSONDecoder().decode(StoredSession.self, from: data) {
            let restored = RoomSession(room: session.room, member: session.member)
            current = restored.room.isJoinable ? restored : nil
        }
    }

    func leave() {
        current = nil
    }

    private struct StoredSession: Codable {
        var room: DiningRoom
        var member: RoomMember
    }

    private func persist() {
        if let current {
            let data = try? JSONEncoder().encode(StoredSession(room: current.room, member: current.member))
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - 暱稱記憶

    static func rememberedDisplayName(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: "displayName") ?? ""
    }

    static func rememberDisplayName(_ name: String, defaults: UserDefaults = .standard) {
        defaults.set(name, forKey: "displayName")
    }
}
