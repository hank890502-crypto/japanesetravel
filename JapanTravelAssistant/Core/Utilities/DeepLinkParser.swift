import Foundation

/// 解析 App 收到的連結。
/// 目前：jptravel://join?code=A8F3K2
/// Web Guest：https://<WEB_GUEST_URL 的主機>/…?code=A8F3K2 或 …/room/A8F3K2（只接受設定裡那個網站）
enum DeepLink: Hashable, Sendable {
    case joinRoom(code: String)
}

enum DeepLinkParser {
    static let scheme = "jptravel"

    /// - webGuestHost：設定裡 Web Guest 網頁的主機（AppConfig.webGuestURL?.host）。
    ///   nil 表示沒有設定網頁版，這時任何 http/https 連結都不算房間連結，
    ///   免得餐廳桌上的官網、優惠 QR Code（也常帶 ?code=）被當成房間代碼送出去。
    static func parse(_ url: URL, webGuestHost: String? = nil) -> DeepLink? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        if components.scheme?.lowercased() == scheme, components.host?.lowercased() == "join" {
            return joinRoom(rawCode: components.queryItems?.first(where: { $0.name == "code" })?.value)
        }

        // Web 連結：只接受設定中的 Web Guest 主機
        if let httpScheme = components.scheme?.lowercased(), httpScheme == "https" || httpScheme == "http" {
            guard let webGuestHost = webGuestHost?.nilIfBlank, let host = components.host,
                  host.lowercased() == webGuestHost.lowercased() else { return nil }
            if let code = components.queryItems?.first(where: { $0.name == "code" })?.value?.nilIfBlank {
                return joinRoom(rawCode: code)
            }
            let parts = components.path.split(separator: "/").map(String.init)
            if let index = parts.firstIndex(of: "room"), index + 1 < parts.count {
                return joinRoom(rawCode: parts[index + 1])
            }
        }
        return nil
    }

    /// 代碼要先清理再檢查長度與字元，不合法就不是房間連結。
    private static func joinRoom(rawCode: String?) -> DeepLink? {
        guard let rawCode = rawCode?.nilIfBlank else { return nil }
        let code = RoomCodeGenerator.normalize(rawCode)
        guard RoomCodeGenerator.isValid(code) else { return nil }
        return .joinRoom(code: code)
    }

    /// App 專用連結（自訂 scheme）。
    static func joinURL(code: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "join"
        components.queryItems = [URLQueryItem(name: "code", value: code)]
        return components.url!
    }

    /// 分享與 QR Code 用的連結：有 Web Guest 網址就用 https（內建相機也能掃、沒 App 也能點），否則用 App 專用連結。
    static func shareURL(code: String, webGuestURL: URL?) -> URL {
        guard let webGuestURL, var components = URLComponents(url: webGuestURL, resolvingAgainstBaseURL: false) else {
            return joinURL(code: code)
        }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "code" }
        items.append(URLQueryItem(name: "code", value: code))
        components.queryItems = items
        return components.url ?? joinURL(code: code)
    }
}
