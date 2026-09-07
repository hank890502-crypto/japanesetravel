import Foundation
import Supabase
import Testing
@testable import JapanTravelAssistant

@Suite("Supabase 錯誤翻成白話（依情境）")
struct SupabaseErrorMapperTests {
    private func rls() -> PostgrestError {
        PostgrestError(code: "42501", message: "new row violates row-level security policy for table \"menu_selections\"")
    }

    @Test("同樣是權限被擋，點餐、加入、上傳菜單各自有不同的說法")
    func permissionByContext() {
        let order = SupabaseErrorMapper.map(rls(), context: .setQuantity)
        #expect(order.title == "點餐沒有送出")
        #expect(order.message.contains("重新加入"))
        #expect(!order.message.contains("上傳菜單"))

        let members = SupabaseErrorMapper.map(rls(), context: .members)
        #expect(members.title == "你已經不在這個房間裡")

        let menu = SupabaseErrorMapper.map(rls(), context: .saveMenu)
        #expect(menu.title == "沒有權限")
        #expect(menu.message.contains("建立房間的人"))

        let close = SupabaseErrorMapper.map(rls(), context: .closeRoom)
        #expect(close.title == "只有房主可以關閉房間")
    }

    @Test("check constraint：稱呼太長／數量超過上限")
    func checkViolation() {
        let tooLong = PostgrestError(code: "23514", message: "new row for relation \"room_members\" violates check constraint \"room_members_display_name_check\"")
        #expect(SupabaseErrorMapper.map(tooLong, context: .joinRoom).title == "稱呼太長了")
        #expect(SupabaseErrorMapper.map(tooLong, context: .createRoom).message.contains("30"))
        #expect(SupabaseErrorMapper.map(tooLong, context: .setQuantity).title == "數量超過上限")
    }

    @Test("函式裡 raise 的關鍵字：找不到房間、開太多房、太頻繁、家人不能改價格")
    func raisedKeywords() {
        #expect(SupabaseErrorMapper.map(PostgrestError(code: "P0001", message: "room_not_found"), context: .joinRoom) == .roomNotFound)
        #expect(SupabaseErrorMapper.map(PostgrestError(code: "P0001", message: "too_many_open_rooms"), context: .createRoom).title == "你開的房間太多了")
        #expect(SupabaseErrorMapper.map(PostgrestError(code: "P0001", message: "room_rate_limited"), context: .createRoom).title == "建立得太頻繁了")
        #expect(SupabaseErrorMapper.map(PostgrestError(code: "42501", message: "only_host_can_edit_item"), context: .editMenu).title == "只有房主可以改這個")
    }

    @Test("重複上傳、沒網路、不認識的錯誤各走自己的路")
    func duplicatesNetworkFallback() {
        let dup = PostgrestError(code: "23505", message: "duplicate key value violates unique constraint \"menus_pkey\"")
        #expect(SupabaseErrorMapper.map(dup, context: .saveMenu).title == "這份菜單已經上傳過")
        #expect(SupabaseErrorMapper.map(dup, context: .setQuantity).title == "資料重複了")
        #expect(SupabaseErrorMapper.map(URLError(.notConnectedToInternet), context: .setQuantity) == .networkUnavailable)
        #expect(SupabaseErrorMapper.map(URLError(.badServerResponse), context: .setQuantity) == .networkUnavailable)
        #expect(SupabaseErrorMapper.map(PostgrestError(code: "XX000", message: "something odd"), context: .createRoom).title == "無法建立房間")
        #expect(SupabaseErrorMapper.map(PostgrestError(code: "XX000", message: "something odd"), context: .members) == .syncUnavailable)
        // 已經是白話錯誤就原樣回傳
        #expect(SupabaseErrorMapper.map(UserFacingError.roomEnded, context: .members) == .roomEnded)
    }
}
