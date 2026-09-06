import Foundation

/// App 啟動設定。值來自 xcconfig → Info.plist，缺值時對應功能自動關閉，不會 crash。
struct AppConfig: Sendable {
    var supabaseURL: URL?
    var supabaseAnonKey: String?
    /// Web Guest 網頁網址（選填）。有的話 QR Code / 分享用 https 連結。
    var webGuestURL: URL?

    /// 多人點餐（Supabase）是否已設定。
    var isCollaborationConfigured: Bool { supabaseURL != nil && supabaseAnonKey != nil }

    static func fromBundle(_ bundle: Bundle = .main) -> AppConfig {
        let urlString = (bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String)?.nilIfBlank
        let key = (bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String)?.nilIfBlank

        var url: URL? = nil
        if let urlString, !urlString.contains("your-project-ref"), let parsed = URL(string: urlString), parsed.host != nil {
            url = parsed
        }
        let cleanKey = (key?.contains("your-anon") == true) ? nil : key

        let webString = (bundle.object(forInfoDictionaryKey: "WEB_GUEST_URL") as? String)?.nilIfBlank
        let webURL = webString.flatMap { URL(string: $0) }.flatMap { $0.host == nil || $0.host == "example.com" ? nil : $0 }
        return AppConfig(supabaseURL: url, supabaseAnonKey: cleanKey, webGuestURL: webURL)
    }

    static let empty = AppConfig(supabaseURL: nil, supabaseAnonKey: nil, webGuestURL: nil)
}
