import Foundation
import Testing
@testable import JapanTravelAssistant

@Suite("Deep link")
struct DeepLinkParserTests {
    @Test("jptravel://join?code=…")
    func parsesCustomScheme() {
        let url = URL(string: "jptravel://join?code=a8f3k2")!
        #expect(DeepLinkParser.parse(url) == .joinRoom(code: "A8F3K2"))
    }

    @Test("未來的 https://…/room/… 也能解析")
    func parsesWebLink() {
        let url = URL(string: "https://example.com/room/A8F3K2")!
        #expect(DeepLinkParser.parse(url) == .joinRoom(code: "A8F3K2"))
    }

    @Test("產生的連結可以被自己解析")
    func roundTrip() {
        let url = DeepLinkParser.joinURL(code: "A8F3K2")
        #expect(DeepLinkParser.parse(url) == .joinRoom(code: "A8F3K2"))
    }

    @Test("Web Guest 連結：?code= 與 /room/ 都能解析，分享連結依設定切換")
    func webGuestLinks() {
        #expect(DeepLinkParser.parse(URL(string: "https://user.github.io/jptravel/?code=a8f3k2")!) == .joinRoom(code: "A8F3K2"))
        #expect(DeepLinkParser.parse(URL(string: "https://example.com/app/room/A8F3K2")!) == .joinRoom(code: "A8F3K2"))
        let web = URL(string: "https://user.github.io/jptravel/")!
        #expect(DeepLinkParser.shareURL(code: "A8F3K2", webGuestURL: web).absoluteString == "https://user.github.io/jptravel/?code=A8F3K2")
        #expect(DeepLinkParser.shareURL(code: "A8F3K2", webGuestURL: nil).absoluteString == "jptravel://join?code=A8F3K2")
        #expect(DeepLinkParser.parse(DeepLinkParser.shareURL(code: "A8F3K2", webGuestURL: web)) == .joinRoom(code: "A8F3K2"))
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
        #expect(DeepLinkParser.parse(URL(string: "jptravel://other")!) == nil)
    }
}
