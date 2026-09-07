import Testing
@testable import JapanTravelAssistant

@Suite("導覽堆疊")
@MainActor
struct AppRouterTests {
    @Test("popOrReplace：目標不在堆疊裡時取代目前這一頁（匯入完成頁不會留在返回路徑上）")
    func replacesTopWhenMissing() {
        let router = AppRouter()
        router.path = [.understandHub, .restaurantHub, .menuScan, .chatGPTImport]
        router.popOrReplace(.menuReview)
        #expect(router.path == [.understandHub, .restaurantHub, .menuScan, .menuReview])
    }

    @Test("popOrReplace：目標已在堆疊裡時直接回到那一頁")
    func popsWhenPresent() {
        let router = AppRouter()
        router.path = [.understandHub, .restaurantHub, .menuScan, .menuReview, .chatGPTImport]
        router.popOrReplace(.menuReview)
        #expect(router.path == [.understandHub, .restaurantHub, .menuScan, .menuReview])
    }

    @Test("popOrReplace：空堆疊就直接 push")
    func pushesWhenEmpty() {
        let router = AppRouter()
        router.popOrReplace(.menuReview)
        #expect(router.path == [.menuReview])
    }

    @Test("popOrPush 維持原本行為：不在堆疊裡就 push")
    func popOrPushStillPushes() {
        let router = AppRouter()
        router.path = [.understandHub]
        router.popOrPush(.settings)
        #expect(router.path == [.understandHub, .settings])
        router.popOrPush(.understandHub)
        #expect(router.path == [.understandHub])
    }
}
