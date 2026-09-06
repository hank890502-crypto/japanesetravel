import Foundation

/// 菜單：把本機草稿上傳到房間、讀取、修改品項。
protocol MenuRepository: Sendable {
    /// 把菜單（含分類、品項）存進某個房間。回傳綁定 roomId 後的版本。
    func saveMenu(_ bundle: MenuBundle, toRoom roomId: UUID) async throws -> MenuBundle
    func menus(roomId: UUID) async throws -> [MenuBundle]
    func updateItem(_ item: MenuItem) async throws
    func deleteItem(id: UUID) async throws
    /// 房間內所有菜單的即時更新。第一個值是目前狀態。
    func observeMenus(roomId: UUID) async -> AsyncStream<[MenuBundle]>
}
