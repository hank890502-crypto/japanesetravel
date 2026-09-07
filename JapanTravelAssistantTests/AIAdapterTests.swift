import Foundation
import Testing
import UIKit
@testable import JapanTravelAssistant

/// 攔截 URLSession 請求，回傳事先準備好的 JSON，測 RemoteAIService 不用真的伺服器。
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("AI Adapter")
struct AIAdapterTests {
    @Test("預設未啟用：呼叫會得到白話錯誤，不會 crash")
    func disabledByDefault() async {
        let router = AIServiceRouter()
        #expect(!router.isEnabled)
        await #expect(throws: UserFacingError.self) {
            _ = try await router.translate("唐揚げ", to: .traditionalChinese)
        }
    }

    @Test("切換到測試用假資料後立刻生效；沒有網址的自己的伺服器等於未啟用")
    @MainActor
    func switching() async throws {
        let router = AIServiceRouter()
        let defaults = UserDefaults(suiteName: "AIAdapterTests.switching")!
        defaults.removePersistentDomain(forName: "AIAdapterTests.switching")
        let settings = SettingsStore(defaults: defaults, aiRouter: router)

        settings.aiProvider = .mock
        #expect(router.isEnabled)
        let translation = try await router.translate("手羽先", to: .traditionalChinese)
        #expect(translation.translated == "雞翅")

        settings.aiProvider = .remoteBackend
        settings.aiBackendURLText = "not a url"
        #expect(settings.effectiveAIProvider == .disabled)
        #expect(!router.isEnabled)

        settings.aiBackendURLText = "https://example.supabase.co/functions/v1/ai"
        #expect(settings.effectiveAIProvider == .remoteBackend)
        #expect(router.isEnabled)
        #expect(router.providerName == AIProviderKind.remoteBackend.displayName)

        // 設定會存起來
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.aiProvider == .remoteBackend)
        #expect(reloaded.aiBackendURL?.host == "example.supabase.co")
    }

    @Test("Mock 的菜單分析可以直接合併進草稿（中文、分類、選項）")
    @MainActor
    func mockMenuAnalysisMerges() async throws {
        let store = MenuDraftStore(directory: nil)
        store.draft = MenuDraft(items: [MenuItemDraft(japaneseName: "若どり唐揚げ", priceText: "540", ocrText: "若どり唐揚げ ¥540")])
        let blocks = [RecognizedTextBlock(text: "若どり唐揚げ ¥540", confidence: 1, boundingBox: .zero), RecognizedTextBlock(text: "生ビール ¥650", confidence: 1, boundingBox: .zero)]
        let analysis = try await MockAIService().analyzeMenu(textBlocks: blocks, image: nil)
        let summary = store.merge(imported: analysis.importedItems)
        #expect(summary.updated == 1 && summary.added == 1)
        let items = store.draft!.items
        #expect(items[0].chineseName == "炸嫩雞")
        #expect(items[0].sectionName == "揚げ物")
        #expect(store.draft!.sectionChineseNames["揚げ物"] == "炸物")
        #expect(items[1].japaneseName == "生ビール" && items[1].sectionName == "ドリンク")
    }

    @Test("RemoteAIService：照約定的 JSON 呼叫與解析；伺服器錯誤變成白話訊息")
    func remoteService() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        let service = RemoteAIService(baseURL: URL(string: "https://example.supabase.co/functions/v1/ai")!, session: session)

        StubURLProtocol.handler = { request in
            guard request.url?.path.hasSuffix("/ai/menu/analyze") == true else { return (404, Data()) }
            let body = """
            {"restaurantName":"酒津屋","items":[{"japanese":"とんかつ","chinese":"炸豬排","reading":"tonkatsu","price":540,"section":"揚げ物","sectionChinese":"炸物",
              "options":[{"group":"份量","japanese":"大盛り","chinese":"大份","priceDelta":150}]}]}
            """
            return (200, Data(body.utf8))
        }
        let analysis = try await service.analyzeMenu(textBlocks: [RecognizedTextBlock(text: "とんかつ 540円", confidence: 1, boundingBox: .zero)], image: nil)
        #expect(analysis.restaurantName == "酒津屋")
        #expect(analysis.items.first?.chineseName == "炸豬排")
        #expect(analysis.items.first?.options.first?.priceDelta == 150)
        #expect(analysis.importedItems.first?.sectionChinese == "炸物")

        StubURLProtocol.handler = { _ in (500, Data("{\"error\":\"boom\"}".utf8)) }
        await #expect(throws: UserFacingError.self) {
            _ = try await service.translate("手羽先", to: .traditionalChinese)
        }

        StubURLProtocol.handler = { _ in (200, Data("not json".utf8)) }
        do {
            _ = try await service.translate("手羽先", to: .traditionalChinese)
            Issue.record("應該要丟出格式錯誤")
        } catch let error as UserFacingError {
            #expect(error.title == "AI 回覆的格式不對")
        }
    }

    @Test("伺服器密碼：有填就放在 X-App-Token；沒填不送；伺服器回 401 給白話提示")
    func remoteServiceToken() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        let base = URL(string: "https://example.supabase.co/functions/v1/ai")!

        StubURLProtocol.handler = { request in
            guard request.value(forHTTPHeaderField: "X-App-Token") == "secret-123" else { return (401, Data("{\"error\":\"unauthorized\"}".utf8)) }
            return (200, Data("{\"translated\":\"雞翅\",\"reading\":\"tebasaki\"}".utf8))
        }
        let withToken = RemoteAIService(baseURL: base, appToken: "secret-123", session: session)
        #expect(try await withToken.translate("手羽先", to: .traditionalChinese).translated == "雞翅")

        let withoutToken = RemoteAIService(baseURL: base, session: session)
        do {
            _ = try await withoutToken.translate("手羽先", to: .traditionalChinese)
            Issue.record("沒有密碼應該被擋")
        } catch let error as UserFacingError {
            #expect(error.title == "AI 服務不接受這個密碼")
            #expect(!error.isRetryable)
        }

        // 設定頁的密碼會透過 Router 帶到 RemoteAIService
        let router = AIServiceRouter()
        let defaults = UserDefaults(suiteName: "AIAdapterTests.token")!
        defaults.removePersistentDomain(forName: "AIAdapterTests.token")
        let settings = await MainActor.run { SettingsStore(defaults: defaults, aiRouter: router) }
        await MainActor.run {
            settings.aiProvider = .remoteBackend
            settings.aiBackendURLText = base.absoluteString
            settings.aiBackendTokenText = "secret-123"
        }
        #expect(await MainActor.run { SettingsStore(defaults: defaults).aiBackendTokenText } == "secret-123")
    }
}
