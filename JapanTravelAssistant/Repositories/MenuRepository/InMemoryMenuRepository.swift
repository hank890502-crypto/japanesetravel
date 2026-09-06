import Foundation

actor InMemoryMenuRepository: MenuRepository {
    private var menus: [UUID: Menu] = [:]
    private var sections: [UUID: MenuSection] = [:]
    private var items: [UUID: MenuItem] = [:]
    private var options: [UUID: MenuItemOption] = [:]
    private var observers = ObserverRegistry<[MenuBundle]>()

    init() {}

    func saveMenu(_ bundle: MenuBundle, toRoom roomId: UUID) async throws -> MenuBundle {
        var menu = bundle.menu
        menu.roomId = roomId
        menus[menu.id] = menu
        for section in bundle.sections { sections[section.id] = section }
        for item in bundle.items { items[item.id] = item }
        for option in bundle.options { options[option.id] = option }
        broadcast(roomId: roomId)
        return MenuBundle(menu: menu, sections: bundle.sections, items: bundle.items, options: bundle.options)
    }

    func menus(roomId: UUID) async throws -> [MenuBundle] {
        bundles(roomId: roomId)
    }

    func updateItem(_ item: MenuItem) async throws {
        items[item.id] = item
        if let roomId = menus[item.menuId]?.roomId { broadcast(roomId: roomId) }
    }

    func deleteItem(id: UUID) async throws {
        guard let item = items.removeValue(forKey: id) else { return }
        if let roomId = menus[item.menuId]?.roomId { broadcast(roomId: roomId) }
    }

    func observeMenus(roomId: UUID) async -> AsyncStream<[MenuBundle]> {
        let stream = observers.makeStream(key: roomId) { [weak self] id in
            Task { await self?.removeObserver(id) }
        }
        observers.broadcast(key: roomId, value: bundles(roomId: roomId))
        return stream
    }

    // MARK: - Private

    private func bundles(roomId: UUID) -> [MenuBundle] {
        menus.values
            .filter { $0.roomId == roomId }
            .sorted { $0.createdAt < $1.createdAt }
            .map { menu in
                let menuItems = items.values.filter { $0.menuId == menu.id }.sorted { ($0.sortOrder, $0.japaneseName) < ($1.sortOrder, $1.japaneseName) }
                let itemIds = Set(menuItems.map(\.id))
                return MenuBundle(
                    menu: menu,
                    sections: sections.values.filter { $0.menuId == menu.id }.sorted { $0.sortOrder < $1.sortOrder },
                    items: menuItems,
                    options: options.values.filter { itemIds.contains($0.menuItemId) }.sorted { $0.sortOrder < $1.sortOrder }
                )
            }
    }

    private func broadcast(roomId: UUID) {
        observers.broadcast(key: roomId, value: bundles(roomId: roomId))
    }

    private func removeObserver(_ id: UUID) {
        observers.remove(id: id)
    }
}
