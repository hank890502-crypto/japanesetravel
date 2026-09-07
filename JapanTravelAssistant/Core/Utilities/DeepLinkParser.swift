import Foundation

/// 解析 App 收到的連結。
/// 目前：jptravel://join?code=A8F3K2
/// 未來：https://<domain>/room/A8F3K2（需要 Universal Links，付費開發者帳號）
enum DeepLink: Hashable, Sendable {
    case joinRoom(code: String)
}

enum DeepLinkParser {
    static let scheme = "jptravel"

    static func parse(_ url: URL) -> DeepLink? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        if components.scheme == scheme, components.host == "join" {
            if let code = components.queryItems?.first(where: { $0.name == "code" })?.value?.nilIfBlank {
                return .joinRoom(code: RoomCodeGenerator.normalize(code))
            }
        }

        // Web 連結：https://<domain>/…/room/<code> 或 https://<domain>/…?code=<code>
        if components.scheme == "https" || components.scheme == "http" {
            if let code = components.queryItems?.first(where: { $0.name == "code" })?.value?.nilIfBlank {
                return .joinRoom(code: RoomCodeGenerator.normalize(code))
            }
            let parts = components.path.split(separator: "/").map(String.init)
            if let index = parts.firstIndex(of: "room"), index + 1 < parts.count {
                return .joinRoom(code: RoomCodeGenerator.normalize(parts[index + 1]))
            }
        }
        return nil
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

    /// 「分享」按鈕送出的文字。
    /// 有網頁版網址才說「點這個連結」；沒有的話 jptravel:// 在 LINE／簡訊裡不是可點的連結，改教家人在 App 裡輸入代碼。
    static func shareMessage(roomName: String, code: String, webGuestURL: URL?) -> String {
        if let webGuestURL {
            let link = shareURL(code: code, webGuestURL: webGuestURL)
            return "一起點餐：\(roomName)\n房間代碼：\(code)\n點這個連結加入：\(link.absoluteString)"
        }
        return "一起點餐：\(roomName)\n房間代碼：\(code)\n加入方法：打開「日本旅遊助手」→ 我要看懂這個 → 看菜單、一起點餐 → 加入家人的點餐，輸入代碼 \(code)"
    }
}
