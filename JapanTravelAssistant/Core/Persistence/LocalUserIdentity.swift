import Foundation

/// 這台裝置的本機使用者 id。
/// 在還沒接 Supabase 前用來當 InMemory Repository 的「我」；接上後改用匿名登入的 auth.uid()。
enum LocalUserIdentity {
    private static let key = "localUserId"

    static func userId(defaults: UserDefaults = .standard) -> UUID {
        if let stored = defaults.string(forKey: key), let id = UUID(uuidString: stored) {
            return id
        }
        let id = UUID()
        defaults.set(id.uuidString, forKey: key)
        return id
    }
}
