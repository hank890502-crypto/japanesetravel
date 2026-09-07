import Foundation
import Supabase

struct SupabaseMenuRepository: MenuRepository {
    let service: LiveSupabaseService
    private var client: SupabaseClient { service.client }

    // MARK: - 寫入用的結構（資料表有反正規化的 room_id，Domain Model 沒有）
    // 注意：批次 insert 時 PostgREST 要求每一列的 key 完全一致，所以 nil 一律送 null（不能省略）。

    private struct MenuRow: Encodable {
        var id: UUID; var roomId: UUID; var restaurantName: String?; var createdByUserId: UUID?
        enum CodingKeys: String, CodingKey { case id, roomId, restaurantName, createdByUserId }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id); try c.encode(roomId, forKey: .roomId)
            try c.encode(restaurantName, forKey: .restaurantName); try c.encode(createdByUserId, forKey: .createdByUserId)
        }
    }
    private struct SectionRow: Encodable {
        var id: UUID; var menuId: UUID; var roomId: UUID; var nameJapanese: String; var nameChinese: String?; var sortOrder: Int
        enum CodingKeys: String, CodingKey { case id, menuId, roomId, nameJapanese, nameChinese, sortOrder }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id); try c.encode(menuId, forKey: .menuId); try c.encode(roomId, forKey: .roomId)
            try c.encode(nameJapanese, forKey: .nameJapanese); try c.encode(nameChinese, forKey: .nameChinese); try c.encode(sortOrder, forKey: .sortOrder)
        }
    }
    private struct ItemRow: Encodable {
        var id: UUID; var menuId: UUID; var roomId: UUID; var sectionId: UUID?
        var japaneseName: String; var chineseName: String?; var reading: String?; var description: String?
        var price: Decimal?; var currency: String; var isRecommended: Bool; var sortOrder: Int; var sourceConfidence: Double?
        enum CodingKeys: String, CodingKey { case id, menuId, roomId, sectionId, japaneseName, chineseName, reading, description, price, currency, isRecommended, sortOrder, sourceConfidence }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id); try c.encode(menuId, forKey: .menuId); try c.encode(roomId, forKey: .roomId); try c.encode(sectionId, forKey: .sectionId)
            try c.encode(japaneseName, forKey: .japaneseName); try c.encode(chineseName, forKey: .chineseName); try c.encode(reading, forKey: .reading); try c.encode(description, forKey: .description)
            try c.encode(price, forKey: .price); try c.encode(currency, forKey: .currency); try c.encode(isRecommended, forKey: .isRecommended); try c.encode(sortOrder, forKey: .sortOrder); try c.encode(sourceConfidence, forKey: .sourceConfidence)
        }
    }
    private struct OptionRow: Encodable {
        var id: UUID; var menuItemId: UUID; var roomId: UUID; var groupName: String; var nameJapanese: String; var nameChinese: String?; var priceDelta: Decimal; var sortOrder: Int
        enum CodingKeys: String, CodingKey { case id, menuItemId, roomId, groupName, nameJapanese, nameChinese, priceDelta, sortOrder }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id); try c.encode(menuItemId, forKey: .menuItemId); try c.encode(roomId, forKey: .roomId); try c.encode(groupName, forKey: .groupName)
            try c.encode(nameJapanese, forKey: .nameJapanese); try c.encode(nameChinese, forKey: .nameChinese); try c.encode(priceDelta, forKey: .priceDelta); try c.encode(sortOrder, forKey: .sortOrder)
        }
    }
    private struct ItemUpdate: Encodable {
        var japaneseName: String; var chineseName: String?; var reading: String?; var description: String?
        var price: Decimal?; var sectionId: UUID?; var isRecommended: Bool; var sortOrder: Int
    }

    func saveMenu(_ bundle: MenuBundle, toRoom roomId: UUID) async throws -> MenuBundle {
        let userId = try await service.signInAnonymouslyIfNeeded()
        do {
            var menu = bundle.menu
            menu.roomId = roomId
            try await client.from("menus")
                .insert(MenuRow(id: menu.id, roomId: roomId, restaurantName: menu.restaurantName, createdByUserId: userId))
                .execute()
            if !bundle.sections.isEmpty {
                try await client.from("menu_sections").insert(bundle.sections.map {
                    SectionRow(id: $0.id, menuId: menu.id, roomId: roomId, nameJapanese: $0.nameJapanese, nameChinese: $0.nameChinese, sortOrder: $0.sortOrder)
                }).execute()
            }
            if !bundle.items.isEmpty {
                try await client.from("menu_items").insert(bundle.items.map {
                    ItemRow(id: $0.id, menuId: menu.id, roomId: roomId, sectionId: $0.sectionId,
                            japaneseName: $0.japaneseName, chineseName: $0.chineseName, reading: $0.reading, description: $0.description,
                            price: $0.price, currency: $0.currency, isRecommended: $0.isRecommended, sortOrder: $0.sortOrder, sourceConfidence: $0.sourceConfidence)
                }).execute()
            }
            if !bundle.options.isEmpty {
                try await client.from("menu_item_options").insert(bundle.options.map {
                    OptionRow(id: $0.id, menuItemId: $0.menuItemId, roomId: roomId, groupName: $0.groupName, nameJapanese: $0.nameJapanese, nameChinese: $0.nameChinese, priceDelta: $0.priceDelta, sortOrder: $0.sortOrder)
                }).execute()
            }
            return MenuBundle(menu: menu, sections: bundle.sections, items: bundle.items, options: bundle.options)
        } catch {
            throw SupabaseErrorMapper.map(error, context: .saveMenu)
        }
    }

    func menus(roomId: UUID) async throws -> [MenuBundle] {
        do {
            let key = roomId.uuidString
            async let menus: [Menu] = client.from("menus").select().eq("room_id", value: key).order("created_at").execute().value
            async let sections: [MenuSection] = client.from("menu_sections").select().eq("room_id", value: key).order("sort_order").execute().value
            async let items: [MenuItem] = client.from("menu_items").select().eq("room_id", value: key).order("sort_order").execute().value
            async let options: [MenuItemOption] = client.from("menu_item_options").select().eq("room_id", value: key).order("sort_order").execute().value
            let (allMenus, allSections, allItems, allOptions) = try await (menus, sections, items, options)
            return allMenus.map { menu in
                let menuItems = allItems.filter { $0.menuId == menu.id }
                let itemIds = Set(menuItems.map(\.id))
                return MenuBundle(
                    menu: menu,
                    sections: allSections.filter { $0.menuId == menu.id },
                    items: menuItems,
                    options: allOptions.filter { itemIds.contains($0.menuItemId) }
                )
            }
        } catch {
            throw SupabaseErrorMapper.map(error, context: .selections)
        }
    }

    func updateItem(_ item: MenuItem) async throws {
        do {
            try await client.from("menu_items")
                .update(ItemUpdate(japaneseName: item.japaneseName, chineseName: item.chineseName, reading: item.reading, description: item.description,
                                   price: item.price, sectionId: item.sectionId, isRecommended: item.isRecommended, sortOrder: item.sortOrder))
                .eq("id", value: item.id.uuidString)
                .execute()
        } catch {
            throw SupabaseErrorMapper.map(error, context: .editMenu)
        }
    }

    func deleteItem(id: UUID) async throws {
        do {
            try await client.from("menu_items").delete().eq("id", value: id.uuidString).execute()
        } catch {
            throw SupabaseErrorMapper.map(error, context: .editMenu)
        }
    }

    func observeMenus(roomId: UUID) async -> AsyncStream<[MenuBundle]> {
        SupabaseRealtimeObserver.stream(client: client, roomId: roomId, tables: ["menus", "menu_sections", "menu_items", "menu_item_options"]) {
            try await menus(roomId: roomId)
        }
    }
}
