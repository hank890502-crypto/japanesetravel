import SwiftUI

/// 所有可以「進入」的畫面。新增功能時在這裡加一個 case，並在 RouteDestinationView 對應。
enum Route: Hashable {
    case communicationCategories
    case phraseList(PhraseCategory)
    case understandHub
    case restaurantHub
    case menuScan
    case menuReview
    case chatGPTImport
    case createRoom
    case room
    case orderSummary
    case joinRoom(code: String?)
    case shoppingFindProduct
    case places
    case tripEditor(UUID?)
    case tripPlaces(UUID)
    case tripImport(UUID)
    case tripMap(UUID)
    case placeDetail(UUID)
    case placeSearch(tripId: UUID)
    case placeEditor(tripId: UUID, placeId: UUID?)
    case emergency
    case settings
    case assistant
}

/// 由 RootView 用 alert 顯示的提示：打開連結／檔案時的白話錯誤，或需要使用者決定的問題。
enum RouterPrompt: Hashable, Sendable {
    /// 只有「好」一個按鈕
    case message(UserFacingError)
    /// 已經在另一個房間，要不要離開去加入新的
    case switchRoom(code: String, currentRoomName: String)

    var title: String {
        switch self {
        case .message(let error): error.title
        case .switchRoom: "要離開目前的房間嗎？"
        }
    }

    var message: String {
        switch self {
        case .message(let error): error.message
        case .switchRoom(_, let name): "你現在在「\(name)」房間。加入這個新房間後，就會離開它（你點的東西會留著，之後用代碼可以再回來）。"
        }
    }
}

/// 導覽狀態：一條 NavigationStack 的路徑 + 全螢幕的「給店員看」。
@Observable
@MainActor
final class AppRouter {
    var path: [Route] = []
    var staffDisplay: StaffDisplayContent?
    /// 收到別人分享的旅程檔，等使用者確認匯入
    var receivedTrip: TripPackage?
    /// 要用 alert 顯示的提示（RootView 負責顯示）
    var prompt: RouterPrompt?
    /// 設定裡 Web Guest 網頁的主機；只有這個主機的 https 連結才算房間連結
    var webGuestHost: String?
    /// 系統把別人分享的檔案複製到這裡；讀完要刪，不然會一直佔空間
    var inboxDirectory: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Inbox", isDirectory: true)

    init(webGuestHost: String? = nil) {
        self.webGuestHost = webGuestHost
    }

    func push(_ route: Route) {
        path.append(route)
    }

    func pop() {
        _ = path.popLast()
    }

    func popToRoot() {
        path.removeAll()
    }

    /// 回到堆疊裡某一頁；不在堆疊裡就 push。
    func popOrPush(_ route: Route) {
        if let index = path.lastIndex(of: route) {
            path.removeSubrange((index + 1)...)
        } else {
            path.append(route)
        }
    }

    /// 回到堆疊裡某一頁；不在堆疊裡就用它「取代」目前這一頁。
    /// 用在「完成頁」之類已經沒有作用的畫面：按上一頁時直接跳過它。
    func popOrReplace(_ route: Route) {
        if path.contains(route) {
            popOrPush(route)
        } else if path.isEmpty {
            path.append(route)
        } else {
            path[path.count - 1] = route
        }
    }

    func showToStaff(_ content: StaffDisplayContent) {
        staffDisplay = content
    }

    /// 處理 jptravel:// 連結，以及別人分享的 .jptrip 旅程檔。
    /// - currentRoom：這台手機目前所在的點餐房間（DiningSessionStore.current），決定收到房間連結時要不要先問。
    func handle(_ url: URL, currentRoom: RoomSession? = nil) {
        if url.isFileURL, url.pathExtension.lowercased() == TripPackage.fileExtension {
            handleTripFile(url)
            return
        }
        guard let link = DeepLinkParser.parse(url, webGuestHost: webGuestHost) else { return }
        switch link {
        case .joinRoom(let code):
            handleJoinRoom(code: code, currentRoom: currentRoom)
        }
    }

    // MARK: - 旅程檔

    private func handleTripFile(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            removeInboxFileIfNeeded(url)
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            let package = try TripPackage.decode(data)
            // 確保確認畫面（sheet）出得來：關掉全螢幕的「給店員看」，並回到沒有全螢幕子頁的地方
            staffDisplay = nil
            path = [.places]
            receivedTrip = package
        } catch {
            receivedTrip = nil
            prompt = .message(error as? UserFacingError ?? .unreadableTripFile)
        }
    }

    /// 只刪 Documents/Inbox 裡的檔案（系統複製過來的那份），其他位置的不動。
    private func removeInboxFileIfNeeded(_ url: URL) {
        guard let inboxDirectory else { return }
        let filePath = url.standardizedFileURL.resolvingSymlinksInPath().path
        let inboxPath = inboxDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        guard filePath.hasPrefix(inboxPath + "/") else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - 房間連結

    private func handleJoinRoom(code: String, currentRoom: RoomSession?) {
        if let currentRoom, currentRoom.room.isJoinable {
            if currentRoom.room.roomCode == code {
                // 已經在這個房間：直接回到點餐畫面，不用重新加入
                staffDisplay = nil
                path = [.understandHub, .restaurantHub, .room]
                return
            }
            prompt = .switchRoom(code: code, currentRoomName: currentRoom.room.name)
            return
        }
        goToJoinRoom(code: code)
    }

    /// 使用者在 alert 裡確認要離開目前房間、加入新的
    func confirmSwitchRoom() {
        guard case .switchRoom(let code, _)? = prompt else { return }
        prompt = nil
        goToJoinRoom(code: code)
    }

    private func goToJoinRoom(code: String) {
        staffDisplay = nil
        path = [.understandHub, .restaurantHub, .joinRoom(code: code)]
    }
}
