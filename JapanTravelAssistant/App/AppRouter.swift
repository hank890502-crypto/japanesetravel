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
    case placeDetail(UUID)
    case placeSearch(tripId: UUID)
    case placeEditor(tripId: UUID, placeId: UUID?)
    case emergency
    case settings
    case assistant
}

/// 導覽狀態：一條 NavigationStack 的路徑 + 全螢幕的「給店員看」。
@Observable
@MainActor
final class AppRouter {
    var path: [Route] = []
    var staffDisplay: StaffDisplayContent?

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

    func showToStaff(_ content: StaffDisplayContent) {
        staffDisplay = content
    }

    /// 處理 jptravel:// 等連結。
    func handle(_ url: URL) {
        guard let link = DeepLinkParser.parse(url) else { return }
        switch link {
        case .joinRoom(let code):
            staffDisplay = nil
            path = [.understandHub, .restaurantHub, .joinRoom(code: code)]
        }
    }
}
