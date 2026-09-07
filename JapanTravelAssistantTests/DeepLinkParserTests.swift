import Foundation
import Testing
@testable import JapanTravelAssistant

@Suite("Deep link")
struct DeepLinkParserTests {
    private let webHost = "user.github.io"

    @Test("jptravel://join?code=…")
    func parsesCustomScheme() {
        let url = URL(string: "jptravel://join?code=a8f3k2")!
        #expect(DeepLinkParser.parse(url) == .joinRoom(code: "A8F3K2"))
    }

    @Test("Web 連結只接受設定裡的 Web Guest 主機")
    func parsesWebLinkOnlyForConfiguredHost() {
        let room = URL(string: "https://user.github.io/jptravel/room/A8F3K2")!
        let query = URL(string: "https://user.github.io/jptravel/?code=a8f3k2")!
        #expect(DeepLinkParser.parse(room, webGuestHost: webHost) == .joinRoom(code: "A8F3K2"))
        #expect(DeepLinkParser.parse(query, webGuestHost: webHost) == .joinRoom(code: "A8F3K2"))
        #expect(DeepLinkParser.parse(query, webGuestHost: "USER.GITHUB.IO") == .joinRoom(code: "A8F3K2"))
        // 沒設定網頁版：任何 https 都不算
        #expect(DeepLinkParser.parse(room) == nil)
        #expect(DeepLinkParser.parse(query, webGuestHost: nil) == nil)
        // 別的網站
        #expect(DeepLinkParser.parse(URL(string: "https://other.site/room/A8F3K2")!, webGuestHost: webHost) == nil)
        #expect(DeepLinkParser.parse(URL(string: "https://example.com/?code=A8F3K2")!, webGuestHost: webHost) == nil)
    }

    @Test("餐廳桌上的官網／優惠 QR 不會被當成房間")
    func ignoresMarketingLinks() {
        #expect(DeepLinkParser.parse(URL(string: "https://example.com/?code=PROMO2026")!) == nil)
        #expect(DeepLinkParser.parse(URL(string: "https://example.com/?code=PROMO2026")!, webGuestHost: webHost) == nil)
        #expect(DeepLinkParser.parse(URL(string: "https://example.com/about?code=hello-world-this-is-long")!, webGuestHost: "example.com") == nil)
        #expect(DeepLinkParser.parse(URL(string: "https://shop.jp/room/reserve")!) == nil)
        #expect(DeepLinkParser.parse(URL(string: "https://shop.jp/room/reserve")!, webGuestHost: webHost) == nil)
        #expect(DeepLinkParser.parse(URL(string: "https://user.github.io/room/reservation-now")!, webGuestHost: webHost) == nil)   // 代碼不合法（太長）
        #expect(DeepLinkParser.parse(URL(string: "jptravel://join?code=hello-world-this-is-long")!) == nil)
        #expect(DeepLinkParser.parse(URL(string: "jptravel://join?code=")!) == nil)
    }

    @Test("產生的連結可以被自己解析")
    func roundTrip() {
        let url = DeepLinkParser.joinURL(code: "A8F3K2")
        #expect(DeepLinkParser.parse(url) == .joinRoom(code: "A8F3K2"))
    }

    @Test("Web Guest 分享連結依設定切換，而且自己解析得回來")
    func webGuestLinks() {
        let web = URL(string: "https://user.github.io/jptravel/")!
        #expect(DeepLinkParser.shareURL(code: "A8F3K2", webGuestURL: web).absoluteString == "https://user.github.io/jptravel/?code=A8F3K2")
        #expect(DeepLinkParser.shareURL(code: "A8F3K2", webGuestURL: nil).absoluteString == "jptravel://join?code=A8F3K2")
        #expect(DeepLinkParser.parse(DeepLinkParser.shareURL(code: "A8F3K2", webGuestURL: web), webGuestHost: web.host) == .joinRoom(code: "A8F3K2"))
    }

    @Test("分享文字：有網頁版才寫「點這個連結」；沒有就教家人在 App 輸入代碼，不放 jptravel:// 字串")
    func shareMessage() {
        let web = URL(string: "https://user.github.io/jptravel/")!
        let withWeb = DeepLinkParser.shareMessage(roomName: "酒津屋晚餐", code: "A8F3K2", webGuestURL: web)
        #expect(withWeb.contains("點這個連結加入：https://user.github.io/jptravel/?code=A8F3K2"))
        #expect(withWeb.contains("房間代碼：A8F3K2"))

        let withoutWeb = DeepLinkParser.shareMessage(roomName: "酒津屋晚餐", code: "A8F3K2", webGuestURL: nil)
        #expect(!withoutWeb.contains("jptravel://"))
        #expect(!withoutWeb.contains("點這個連結"))
        #expect(withoutWeb.contains("加入家人的點餐"))
        #expect(withoutWeb.contains("輸入代碼 A8F3K2"))
    }

    @Test("不認識的連結回 nil")
    func ignoresUnknown() {
        #expect(DeepLinkParser.parse(URL(string: "https://example.com/about")!) == nil)
        #expect(DeepLinkParser.parse(URL(string: "https://user.github.io/about")!, webGuestHost: webHost) == nil)
        #expect(DeepLinkParser.parse(URL(string: "jptravel://other")!) == nil)
    }
}
