import Foundation
import Observation

/// 使用者可以改的設定：AI 幫手、預設地圖 App。存在 UserDefaults；改了立刻套用到 AIServiceRouter。
@Observable
@MainActor
final class SettingsStore {
    var aiProvider: AIProviderKind { didSet { save(); applyAI() } }
    var aiBackendURLText: String { didSet { save(); applyAI() } }
    var navigationProvider: NavigationProvider { didSet { save() } }

    private let defaults: UserDefaults
    private let aiRouter: AIServiceRouter?

    init(defaults: UserDefaults = .standard, aiRouter: AIServiceRouter? = nil) {
        self.defaults = defaults
        self.aiRouter = aiRouter
        // 沒設定過：裝置支援 Apple 智慧就預設用它（免費、離線）
        aiProvider = defaults.string(forKey: Keys.aiProvider).flatMap(AIProviderKind.init(rawValue:))
            ?? (AppleIntelligence.availability.isAvailable ? .appleIntelligence : .disabled)
        aiBackendURLText = defaults.string(forKey: Keys.aiBackendURL) ?? ""
        navigationProvider = defaults.string(forKey: Keys.navigation).flatMap(NavigationProvider.init(rawValue:)) ?? .appleMaps
        applyAI()
    }

    var aiBackendURL: URL? {
        guard let url = URL(string: aiBackendURLText.trimmingCharacters(in: .whitespaces)), let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil else { return nil }
        return url
    }

    /// 自己的伺服器但網址無效、或 Apple 智慧不可用 → 實際上等於未啟用
    var effectiveAIProvider: AIProviderKind {
        switch aiProvider {
        case .remoteBackend where aiBackendURL == nil: return .disabled
        case .appleIntelligence where !AppleIntelligence.availability.isAvailable: return .disabled
        default: return aiProvider
        }
    }

    private enum Keys {
        static let aiProvider = "settings.aiProvider"
        static let aiBackendURL = "settings.aiBackendURL"
        static let navigation = "settings.navigationProvider"
    }

    private func save() {
        defaults.set(aiProvider.rawValue, forKey: Keys.aiProvider)
        defaults.set(aiBackendURLText, forKey: Keys.aiBackendURL)
        defaults.set(navigationProvider.rawValue, forKey: Keys.navigation)
    }

    private func applyAI() {
        aiRouter?.update(kind: effectiveAIProvider, backendURL: aiBackendURL)
    }
}
