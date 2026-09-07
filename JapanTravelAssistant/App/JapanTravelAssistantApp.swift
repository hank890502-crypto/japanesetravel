import SwiftUI

@main
struct JapanTravelAssistantApp: App {
    private let dependencies: AppDependencies
    @State private var router = AppRouter()
    @State private var menuDraftStore = MenuDraftStore()
    @State private var sessionStore = DiningSessionStore()
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
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.dependencies, dependencies)
                .environment(router)
                .environment(menuDraftStore)
                .environment(sessionStore)
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
