import SwiftUI

@main
struct JapanTravelAssistantApp: App {
    private let dependencies: AppDependencies
    @State private var router = AppRouter()
    @State private var menuDraftStore = MenuDraftStore()
    @State private var sessionStore: DiningSessionStore
    @State private var roomCoordinator: RoomSessionCoordinator
    @State private var settingsStore: SettingsStore
    @State private var placeStore = PlaceStore()

    init() {
        let deps = AppDependencies.live(config: DebugLaunchOptions.forcesInMemory() ? .empty : AppConfig.fromBundle())
        dependencies = deps
        _settingsStore = State(initialValue: SettingsStore(aiRouter: deps.aiRouter))
        let router = AppRouter()
        router.path = DebugLaunchOptions.initialPath()
        _router = State(initialValue: router)
        if let sample = DebugLaunchOptions.sampleDraft() {
            let store = MenuDraftStore()
            store.draft = sample
            _menuDraftStore = State(initialValue: store)
        }
        let sessionStore = DiningSessionStore()
        // 沒有連上多人點餐時房間只存在記憶體裡，App 一關就沒了：不要還原一個已經不存在的房間
        if !deps.config.isCollaborationConfigured { sessionStore.leave() }
        _sessionStore = State(initialValue: sessionStore)
        _roomCoordinator = State(initialValue: RoomSessionCoordinator(
            sessionStore: sessionStore,
            roomRepository: deps.roomRepository,
            menuRepository: deps.menuRepository,
            orderRepository: deps.orderRepository
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.dependencies, dependencies)
                .environment(router)
                .environment(menuDraftStore)
                .environment(sessionStore)
                .environment(roomCoordinator)
                .environment(settingsStore)
                .environment(placeStore)
                .task { DebugLaunchOptions.seedPlacesIfRequested(into: placeStore, router: router) }
                .task { await DebugLaunchOptions.seedRoomIfRequested(dependencies: dependencies, sessionStore: sessionStore, router: router) }
                .onOpenURL { url in
                    router.handle(url)
                }
        }
    }
}
