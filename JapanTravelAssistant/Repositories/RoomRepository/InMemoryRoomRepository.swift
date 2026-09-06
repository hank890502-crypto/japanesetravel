import Foundation

/// 只存在記憶體裡的房間資料。給 Preview、測試，以及尚未設定 Supabase 時使用。
actor InMemoryRoomRepository: RoomRepository {
    private var rooms: [UUID: DiningRoom] = [:]
    private var members: [UUID: RoomMember] = [:]
    private var memberObservers = ObserverRegistry<[RoomMember]>()
    private let currentUserId: UUID

    init(currentUserId: UUID = UUID()) {
        self.currentUserId = currentUserId
    }

    func createRoom(name: String, hostDisplayName: String, preferredCode: String?) async throws -> RoomSession {
        var code = RoomCodeGenerator.generate()
        if let preferred = preferredCode.map(RoomCodeGenerator.normalize), RoomCodeGenerator.isValid(preferred) {
            // 指定代碼：舊的同代碼房間先關掉
            for (id, room) in rooms where room.roomCode == preferred { rooms[id]?.status = .closed }
            code = preferred
        }
        while rooms.values.contains(where: { $0.roomCode == code && $0.status == .open }) {
            code = RoomCodeGenerator.generate()
        }
        let room = DiningRoom(name: name.nilIfBlank ?? "一起點餐", roomCode: code, hostUserId: currentUserId)
        let host = RoomMember(roomId: room.id, userId: currentUserId, displayName: hostDisplayName.nilIfBlank ?? "房主", isHost: true)
        rooms[room.id] = room
        members[host.id] = host
        broadcastMembers(roomId: room.id)
        return RoomSession(room: room, member: host)
    }

    func joinRoom(code: String, displayName: String) async throws -> RoomSession {
        let normalized = RoomCodeGenerator.normalize(code)
        guard let room = rooms.values.first(where: { $0.roomCode == normalized && $0.isJoinable }) else {
            throw UserFacingError.roomNotFound
        }
        let name = displayName.nilIfBlank ?? "家人"
        if var existing = members.values.first(where: { $0.roomId == room.id && $0.userId == currentUserId }) {
            existing.displayName = name
            members[existing.id] = existing
            broadcastMembers(roomId: room.id)
            return RoomSession(room: room, member: existing)
        }
        let member = RoomMember(roomId: room.id, userId: currentUserId, displayName: name, isHost: room.hostUserId == currentUserId)
        members[member.id] = member
        broadcastMembers(roomId: room.id)
        return RoomSession(room: room, member: member)
    }

    func members(roomId: UUID) async throws -> [RoomMember] {
        membersList(roomId: roomId)
    }

    func observeMembers(roomId: UUID) async -> AsyncStream<[RoomMember]> {
        let stream = memberObservers.makeStream(key: roomId) { [weak self] id in
            Task { await self?.removeMemberObserver(id) }
        }
        memberObservers.broadcast(key: roomId, value: membersList(roomId: roomId))
        return stream
    }

    func closeRoom(roomId: UUID) async throws {
        rooms[roomId]?.status = .closed
    }

    // MARK: - 測試輔助

    /// 模擬「另一個人」加入（測試 / Preview 用）。
    func addMember(roomId: UUID, displayName: String) -> RoomMember {
        let member = RoomMember(roomId: roomId, userId: UUID(), displayName: displayName)
        members[member.id] = member
        broadcastMembers(roomId: roomId)
        return member
    }

    // MARK: - Private

    private func membersList(roomId: UUID) -> [RoomMember] {
        members.values.filter { $0.roomId == roomId }.sorted { $0.createdAt < $1.createdAt }
    }

    private func broadcastMembers(roomId: UUID) {
        memberObservers.broadcast(key: roomId, value: membersList(roomId: roomId))
    }

    private func removeMemberObserver(_ id: UUID) {
        memberObservers.remove(id: id)
    }
}
