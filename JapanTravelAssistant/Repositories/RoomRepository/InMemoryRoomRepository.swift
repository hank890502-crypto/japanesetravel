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

    func createRoom(name: String, hostDisplayName: String) async throws -> RoomSession {
        var code = RoomCodeGenerator.generate()
        while rooms.values.contains(where: { $0.roomCode == code && $0.status == .open }) {
            code = RoomCodeGenerator.generate()
        }
        let room = DiningRoom(name: name.nilIfBlank ?? "一起點餐", roomCode: code, hostUserId: currentUserId)
        let host = RoomMember(roomId: room.id, userId: currentUserId, displayName: RoomMember.clampDisplayName(hostDisplayName.nilIfBlank ?? "房主"), isHost: true)
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
        let name = RoomMember.clampDisplayName(displayName.nilIfBlank ?? "家人")
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

    func restoreSession(_ session: RoomSession) async throws -> RoomSession {
        // 記憶體裡的房間 App 一關就沒了：找不到或已結束就明確告訴上層，不要顯示一個空房間
        guard let room = rooms[session.room.id], room.isJoinable else { throw UserFacingError.roomEnded }
        if let member = members[session.member.id], member.roomId == room.id {
            return RoomSession(room: room, member: member)
        }
        // 這台手機已不是成員（例如身分變了）：房主拿不回房間，家人可以重新加入
        if session.member.isHost { throw UserFacingError.roomNeedsRecreate }
        return try await joinRoom(code: room.roomCode, displayName: session.member.displayName)
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

    /// 模擬「成員被移除／房間資料消失」（測試用）。
    func removeMember(id: UUID) {
        guard let member = members.removeValue(forKey: id) else { return }
        broadcastMembers(roomId: member.roomId)
    }

    /// 模擬「房間已超過 48 小時」（測試用）。
    func expireRoom(id: UUID) {
        rooms[id]?.expiresAt = .now.addingTimeInterval(-1)
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
