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
        .sheet(item: $router.receivedTrip) { package in
            TripReceiveView(package: package)
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
            TripsView()
        case .tripEditor(let id):
            TripEditorView(tripId: id)
        case .tripPlaces(let id):
            TripPlacesView(tripId: id)
        case .tripImport(let id):
            TripImportView(tripId: id)
        case .tripMap(let id):
            TripMapView(tripId: id)
        case .placeDetail(let id):
            PlaceDetailView(placeId: id)
        case .placeSearch(let tripId):
            PlaceSearchView(tripId: tripId)
        case .placeEditor(let tripId, let placeId):
            PlaceEditorView(tripId: tripId, placeId: placeId)
        case .emergency:
            EmergencyView()
        case .settings:
            SettingsView()
        case .assistant:
            AssistantView()
        }
    }
}

#Preview {
    let sessionStore = DiningSessionStore(defaults: UserDefaults(suiteName: "preview")!)
    RootView()
        .environment(AppRouter())
        .environment(MenuDraftStore(directory: nil))
        .environment(sessionStore)
        .environment(RoomSessionCoordinator.preview(sessionStore: sessionStore))
        .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview")!))
        .environment(PlaceStore(directory: nil))
        .environment(\.dependencies, .preview)
}
