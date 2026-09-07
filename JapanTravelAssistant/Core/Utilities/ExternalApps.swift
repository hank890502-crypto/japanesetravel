import UIKit

/// 打開別的 App：裝了就開 App，沒裝就開網頁版。
enum ExternalApps {
    @MainActor
    static func openChatGPT() {
        let app = URL(string: "chatgpt://")!
        let web = URL(string: "https://chatgpt.com")!
        UIApplication.shared.open(UIApplication.shared.canOpenURL(app) ? app : web)
    }
}
