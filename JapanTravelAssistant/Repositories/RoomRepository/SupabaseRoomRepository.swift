import Foundation
import Supabase

struct SupabaseRoomRepository: RoomRepository {
    let service: LiveSupabaseService
    private var client: SupabaseClient { service.client }

    private struct SessionResponse: Decodable {
        var room: DiningRoom
        var member: RoomMember
    }

    func createRoom(name: String, hostDisplayName: String) async throws -> RoomSession {
        _ = try await service.signInAnonymouslyIfNeeded()
        do {
            let response: SessionResponse = try await client
                .rpc("create_room", params: ["p_name": name, "p_display_name": RoomMember.clampDisplayName(hostDisplayName)])
                .execute()
                .value
            return RoomSession(room: response.room, member: response.member)
        } catch {
            throw SupabaseErrorMapper.map(error, context: .createRoom)
        }
    }

    func joinRoom(code: String, displayName: String) async throws -> RoomSession {
        _ = try await service.signInAnonymouslyIfNeeded()
        do {
            let response: SessionResponse = try await client
                .rpc("join_room", params: ["p_code": RoomCodeGenerator.normalize(code), "p_display_name": RoomMember.clampDisplayName(displayName)])
                .execute()
                .value
            return RoomSession(room: response.room, member: response.member)
        } catch {
            throw SupabaseErrorMapper.map(error, context: .joinRoom)
        }
    }

    func restoreSession(_ session: RoomSession) async throws -> RoomSession {
        let userId = try await service.signInAnonymouslyIfNeeded()
        // 匿名身分換掉了：家人可以用代碼重新加入（下面的 join_room），房主則拿不回房間
        if userId != session.member.userId, session.member.isHost {
            throw UserFacingError.roomNeedsRecreate
        }
        // join_room 是 upsert：同一個人只會更新稱呼並回傳最新的房間／成員；房間已關或過期會回 room_not_found
        do {
            return try await joinRoom(code: session.room.roomCode, displayName: session.member.displayName)
        } catch let error as UserFacingError where error == .roomNotFound {
            throw UserFacingError.roomEnded
        }
    }

    func members(roomId: UUID) async throws -> [RoomMember] {
        do {
            return try await client.from("room_members")
                .select()
                .eq("room_id", value: roomId.uuidString)
                .order("created_at")
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapper.map(error, context: .members)
        }
    }

    func observeMembers(roomId: UUID) async -> AsyncStream<[RoomMember]> {
        SupabaseRealtimeObserver.stream(client: client, roomId: roomId, tables: ["room_members"]) {
            try await members(roomId: roomId)
        }
    }

    func closeRoom(roomId: UUID) async throws {
        do {
            try await client.from("dining_rooms")
                .update(["status": "closed"])
                .eq("id", value: roomId.uuidString)
                .execute()
        } catch {
            throw SupabaseErrorMapper.map(error, context: .closeRoom)
        }
    }
}
