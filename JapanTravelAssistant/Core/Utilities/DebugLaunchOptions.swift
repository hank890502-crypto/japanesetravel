import Foundation

/// 只在 DEBUG 生效的啟動參數，讓自動化截圖／測試可以直接打開某個畫面。
/// 用法：xcrun simctl launch <udid> com.linzihao.japantravelassistant -openRoute emergency
enum DebugLaunchOptions {
    /// -openRoute room / orderSummary 需要單機的示範資料，不碰真正的 Supabase。
    static func forcesInMemory(arguments: [String] = CommandLine.arguments) -> Bool {
        #if DEBUG
        guard let index = arguments.firstIndex(of: "-openRoute"), index + 1 < arguments.count else { return false }
        return ["room", "orderSummary"].contains(arguments[index + 1])
        #else
        return false
        #endif
    }

    /// -openRoute places / tripPlaces / placeDetail / tripImport：放一趟示範旅程方便截圖。
    @MainActor
    static func seedPlacesIfRequested(into store: PlaceStore, router: AppRouter, arguments: [String] = CommandLine.arguments) {
        #if DEBUG
        guard let index = arguments.firstIndex(of: "-openRoute"), index + 1 < arguments.count else { return }
        let route = arguments[index + 1]
        guard ["places", "tripPlaces", "placeDetail", "tripImport"].contains(route) else { return }
        let trip: Trip
        if let existing = store.sortedTrips.first(where: { !store.places(in: $0.id).isEmpty }) ?? store.sortedTrips.first {
            trip = existing
        } else {
            let start = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 12))!
            trip = store.addTrip(name: "9 月名古屋", startDate: start, endDate: Calendar.current.date(byAdding: .day, value: 4, to: start))
            store.addMany([
                Place(name: "我們的飯店", address: "〒450-0002 愛知県名古屋市中村区名駅4丁目", latitude: 35.1706, longitude: 136.8853, category: .hotel, phone: "+81-52-000-0000", note: "退房 11:00", japaneseName: "ドーミーイン名古屋", dayLabel: "第1天 9/12 名古屋"),
                Place(name: "名古屋車站", address: "〒450-0002 愛知県名古屋市中村区名駅1丁目", latitude: 35.1709, longitude: 136.8815, category: .station, japaneseName: "名古屋駅", dayLabel: "第1天 9/12 名古屋"),
                Place(name: "酒津屋（晚餐）", address: "〒460-0008 愛知県名古屋市中区栄3丁目", latitude: 35.1681, longitude: 136.9086, category: .restaurant, japaneseName: "酒津屋", dayLabel: "第1天 9/12 名古屋"),
                Place(name: "名古屋城", address: "〒460-0031 愛知県名古屋市中区本丸1-1", latitude: 35.1856, longitude: 136.8998, category: .sight, note: "9:00–16:30", japaneseName: "名古屋城", dayLabel: "第2天 9/13 名古屋"),
            ], to: trip.id)
            store.addTrip(name: "12 月東京", startDate: Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 20)))
        }
        switch route {
        case "tripPlaces": router.path = [.places, .tripPlaces(trip.id)]
        case "placeDetail": if let first = store.places(in: trip.id).first { router.path = [.places, .tripPlaces(trip.id), .placeDetail(first.id)] }
        case "tripImport": router.path = [.places, .tripPlaces(trip.id), .tripImport(trip.id)]
        default: break
        }
        #endif
    }

    /// -openRoute room / orderSummary：用本機 Repository 建一個有菜單、有家人、有點餐的示範房間。
    @MainActor
    static func seedRoomIfRequested(dependencies: AppDependencies, sessionStore: DiningSessionStore, router: AppRouter, arguments: [String] = CommandLine.arguments) async {
        #if DEBUG
        guard let index = arguments.firstIndex(of: "-openRoute"), index + 1 < arguments.count,
              ["room", "orderSummary"].contains(arguments[index + 1]),
              let draft = sampleDraft(arguments: ["-openRoute", "menuReview"]) else { return }
        guard let roomRepo = dependencies.roomRepository as? InMemoryRoomRepository else { return }
        do {
            let session = try await roomRepo.createRoom(name: "酒津屋晚餐", hostDisplayName: "我")
            let bundle = try await dependencies.menuRepository.saveMenu(draft.toBundle(), toRoom: session.room.id)
            let mom = await roomRepo.addMember(roomId: session.room.id, displayName: "媽媽")
            let dad = await roomRepo.addMember(roomId: session.room.id, displayName: "爸爸")
            let items = bundle.items
            let large = bundle.options.first { $0.nameJapanese == "大盛り" }
            try await dependencies.orderRepository.setQuantity(roomId: session.room.id, memberId: mom.id, menuItemId: items[0].id, optionIds: [], quantity: 1)
            try await dependencies.orderRepository.setQuantity(roomId: session.room.id, memberId: dad.id, menuItemId: items[1].id, optionIds: [], quantity: 2)
            try await dependencies.orderRepository.setQuantity(roomId: session.room.id, memberId: session.member.id, menuItemId: items[2].id, optionIds: large.map { [$0.id] } ?? [], quantity: 1)
            sessionStore.current = session
            router.path = [.understandHub, .restaurantHub, .room] + (arguments[index + 1] == "orderSummary" ? [.orderSummary] : [])
        } catch {
            assertionFailure("示範房間建立失敗：\(error)")
        }
        #endif
    }

    /// -openRoute menuReview / createRoom 時塞入的示範菜單。
    static func sampleDraft(arguments: [String] = CommandLine.arguments) -> MenuDraft? {
        #if DEBUG
        guard let index = arguments.firstIndex(of: "-openRoute"), index + 1 < arguments.count,
              ["menuReview", "createRoom"].contains(arguments[index + 1]) else { return nil }
        return MenuDraft(restaurantName: "酒津屋", items: [
            MenuItemDraft(japaneseName: "若どり唐揚げ", chineseName: "炸嫩雞", priceText: "540", sourceConfidence: 0.95, ocrText: "若どり唐揚げ ¥540", sectionName: "揚げ物"),
            MenuItemDraft(japaneseName: "手羽先", priceText: "430", sourceConfidence: 0.92, ocrText: "手羽先 ¥430", sectionName: "揚げ物"),
            MenuItemDraft(japaneseName: "味噌串カツ", priceText: "540", sourceConfidence: 0.90, ocrText: "味噌串カツ ¥540", sectionName: "揚げ物", options: [
                MenuOptionDraft(groupName: "份量", japaneseName: "大盛り", chineseName: "大份", priceDeltaText: "+150"),
                MenuOptionDraft(groupName: "套餐", japaneseName: "定食セット", chineseName: "升級定食", priceDeltaText: "+300"),
            ]),
            MenuItemDraft(japaneseName: "ねぎま", chineseName: "蔥段雞肉串", priceText: "180", sectionName: "焼き物", note: "雞肉夾蔥"),
            MenuItemDraft(japaneseName: "生ビール", chineseName: "生啤酒", priceText: "650"),
        ], otherLines: [
            MenuItemDraft(japaneseName: "本日のおすすめ", ocrText: "本日のおすすめ"),
            MenuItemDraft(japaneseName: "※価格は税込です", ocrText: "※価格は税込です"),
        ], sectionChineseNames: ["揚げ物": "炸物"])
        #else
        return nil
        #endif
    }

    static func initialPath(arguments: [String] = CommandLine.arguments) -> [Route] {
        #if DEBUG
        guard let index = arguments.firstIndex(of: "-openRoute"), index + 1 < arguments.count else { return [] }
        switch arguments[index + 1] {
        case "communication": return [.communicationCategories]
        case "emergency": return [.emergency]
        case "understand": return [.understandHub]
        case "restaurant": return [.understandHub, .restaurantHub]
        case "menuScan": return [.understandHub, .restaurantHub, .menuScan]
        case "menuReview": return [.understandHub, .restaurantHub, .menuScan, .menuReview]
        case "chatGPTImport": return [.understandHub, .restaurantHub, .menuScan, .chatGPTImport]
        case "createRoom": return [.understandHub, .restaurantHub, .menuScan, .menuReview, .createRoom]
        case "room", "orderSummary": return []   // 由 seedRoomIfRequested 建好房間後再 push
        case "joinRoom": return [.understandHub, .restaurantHub, .joinRoom(code: "A8F3K2")]
        case "findProduct": return [.understandHub, .shoppingFindProduct]
        case "places": return [.places]
        case "settings": return [.settings]
        case let value where value.hasPrefix("phrases:"):
            let raw = String(value.dropFirst("phrases:".count))
            if let category = PhraseCategory(rawValue: raw) { return [.communicationCategories, .phraseList(category)] }
            return []
        default: return []
        }
        #else
        return []
        #endif
    }
}
