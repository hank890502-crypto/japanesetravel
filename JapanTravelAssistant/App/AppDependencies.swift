import SwiftUI

/// 全 App 的相依容器。所有 Service / Repository 都是 protocol，
/// `live` 給真機，`preview` 給 #Preview 與測試。不使用 singleton。
struct AppDependencies {
    let config: AppConfig
    let ocr: any OCRService
    let menuRecognizer: any MenuRecognitionService
    let ai: any AIService
    /// 可切換供應商的 AI 路由（SettingsStore 會更新它）。preview 為 nil。
    let aiRouter: AIServiceRouter?
    let speech: any SpeechService
    let phrases: any PhraseProvider
    let navigation: any NavigationService
    let placeSearch: any PlaceSearchService
    let location: any CurrentLocationProvider
    let geocoder: any PlaceGeocoder
    let supabase: any SupabaseService
    let roomRepository: any RoomRepository
    let menuRepository: any MenuRepository
    let orderRepository: any OrderRepository

    /// 真機用。沒有 Supabase 設定時自動退回 InMemory，App 照常啟動。
    @MainActor
    static func live(config: AppConfig) -> AppDependencies {
        let localUserId = LocalUserIdentity.userId()
        let aiRouter = AIServiceRouter()

        // 有 Supabase 設定 → 真正的多人同步；沒有 → 只在這台手機上運作（仍可完整測試流程）
        if let url = config.supabaseURL, let key = config.supabaseAnonKey {
            let supabase = LiveSupabaseService(url: url, anonKey: key)
            return AppDependencies(
                config: config,
                ocr: VisionOCRService(),
                menuRecognizer: LiveMenuRecognitionService(),
                ai: aiRouter,
                aiRouter: aiRouter,
                speech: AVSpeechService(),
                phrases: BundledPhraseProvider(),
                navigation: LiveNavigationService(),
                placeSearch: LocalPlaceSearchService(),
                location: LiveCurrentLocationProvider(),
                geocoder: LiveGeocoder(),
                supabase: supabase,
                roomRepository: SupabaseRoomRepository(service: supabase),
                menuRepository: SupabaseMenuRepository(service: supabase),
                orderRepository: SupabaseOrderRepository(service: supabase)
            )
        }
        return AppDependencies(
            config: config,
            ocr: VisionOCRService(),
            menuRecognizer: LiveMenuRecognitionService(),
            ai: aiRouter,
            aiRouter: aiRouter,
            speech: AVSpeechService(),
            phrases: BundledPhraseProvider(),
            navigation: LiveNavigationService(),
            placeSearch: LocalPlaceSearchService(),
            location: LiveCurrentLocationProvider(),
            geocoder: LiveGeocoder(),
            supabase: UnconfiguredSupabaseService(),
            roomRepository: InMemoryRoomRepository(currentUserId: localUserId),
            menuRepository: InMemoryMenuRepository(),
            orderRepository: InMemoryOrderRepository()
        )
    }

    /// Preview / 測試用：全部假資料，不需要網路。
    static let preview = AppDependencies(
        config: .empty,
        ocr: MockOCRService(delay: .zero),
        menuRecognizer: MockMenuRecognitionService(),
        ai: MockAIService(),
        aiRouter: nil,
        speech: NoopSpeechService(),
        phrases: BundledPhraseProvider(),
        navigation: MockNavigationService(),
        placeSearch: MockPlaceSearchService(),
        location: MockCurrentLocationProvider(),
        geocoder: MockGeocoder(),
        supabase: UnconfiguredSupabaseService(),
        roomRepository: InMemoryRoomRepository(),
        menuRepository: InMemoryMenuRepository(),
        orderRepository: InMemoryOrderRepository()
    )
}

extension EnvironmentValues {
    @Entry var dependencies: AppDependencies = .preview
}
