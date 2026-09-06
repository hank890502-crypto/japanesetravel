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
