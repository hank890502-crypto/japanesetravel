import Foundation
import Supabase

struct SupabaseRoomRepository: RoomRepository {
    let service: LiveSupabaseService
    private var client: SupabaseClient { service.client }

    private struct SessionResponse: Decodable {
        var room: DiningRoom
        var member: RoomMember
    }

    func createRoom(name: String, hostDisplayName: String, preferredCode: String?) async throws -> RoomSession {
        _ = try await service.signInAnonymouslyIfNeeded()
        do {
            var params = ["p_name": name, "p_display_name": hostDisplayName]
            if let preferredCode { params["p_code"] = RoomCodeGenerator.normalize(preferredCode) }
            let response: SessionResponse = try await client
                .rpc("create_room", params: params)
                .execute()
                .value
            return RoomSession(room: response.room, member: response.member)
        } catch {
            throw SupabaseErrorMapper.map(error, fallback: UserFacingError(title: "無法建立房間", message: "請確認網路連線後再試一次。"))
        }
    }

    func joinRoom(code: String, displayName: String) async throws -> RoomSession {
        _ = try await service.signInAnonymouslyIfNeeded()
        do {
            let response: SessionResponse = try await client
                .rpc("join_room", params: ["p_code": RoomCodeGenerator.normalize(code), "p_display_name": displayName])
                .execute()
                .value
            return RoomSession(room: response.room, member: response.member)
        } catch {
            throw SupabaseErrorMapper.map(error, fallback: UserFacingError(title: "無法加入房間", message: "請確認代碼與網路連線後再試一次。"))
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
            throw SupabaseErrorMapper.map(error, fallback: .syncUnavailable)
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
            throw SupabaseErrorMapper.map(error, fallback: .syncUnavailable)
        }
    }
}

/// 把 Supabase / 網路錯誤翻成白話。
enum SupabaseErrorMapper {
    static func map(_ error: Error, fallback: UserFacingError) -> UserFacingError {
        if let userFacing = error as? UserFacingError { return userFacing }
        #if DEBUG
        print("[Supabase] \(error)")
        #endif
        let description = String(describing: error).lowercased()
        if description.contains("duplicate key") {
            return UserFacingError(title: "這份菜單已經上傳過", message: "請回到「檢查菜單」再按一次「下一步」，App 會用新的資料重新上傳。")
        }
        if description.contains("row-level security") || description.contains("permission denied") {
            return UserFacingError(title: "沒有權限", message: "只有建立房間的人可以上傳菜單。請重新建立一個房間。", isRetryable: false)
        }
        if description.contains("room_not_found") { return .roomNotFound }
        if description.contains("not_authenticated") { return UserFacingError(title: "還沒連上", message: "請再試一次。") }
        if error is URLError { return .networkUnavailable }
        return fallback
    }
}
