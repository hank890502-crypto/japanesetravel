import SwiftUI

/// App 的根：一條 NavigationStack，首頁在最底。
struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    RouteDestinationView(route: route)
                }
        }
        .fullScreenCover(item: $router.staffDisplay) { content in
            StaffDisplayView(content: content) {
                router.staffDisplay = nil
            }
        }
    }
}

/// Route → 實際畫面的對應表。
struct RouteDestinationView: View {
    let route: Route

    var body: some View {
        switch route {
        case .communicationCategories:
            CommunicationCategoriesView()
        case .phraseList(let category):
            PhraseListView(category: category)
        case .understandHub:
            UnderstandHubView()
        case .restaurantHub:
            RestaurantHubView()
        case .menuScan:
            MenuScanView()
        case .menuReview:
            MenuReviewView()
        case .chatGPTImport:
            ChatGPTImportView()
        case .createRoom:
            CreateRoomView()
        case .room:
            RoomView()
        case .orderSummary:
            OrderSummaryView()
        case .joinRoom(let code):
            JoinRoomView(prefilledCode: code)
        case .shoppingFindProduct:
            FindProductView()
        case .places:
            PlacesView()
        case .emergency:
            EmergencyView()
        case .settings:
            SettingsView()
        }
    }
}

#Preview {
    RootView()
        .environment(AppRouter())
        .environment(MenuDraftStore(directory: nil))
        .environment(DiningSessionStore(defaults: UserDefaults(suiteName: "preview")!))
        .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview")!))
        .environment(\.dependencies, .preview)
}
