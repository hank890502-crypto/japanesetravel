import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// 一批要翻譯的文字（id 用來對回原本的品項）。
struct TranslationBatch: Hashable, Identifiable {
    struct Entry: Hashable {
        var id: String
        var text: String
    }
    var id = UUID()
    var entries: [Entry]
}

/// Apple 內建的離線翻譯（日→繁中）。iOS 18 起可以由程式批次呼叫；第一次使用系統會請使用者下載語言包。
enum AppleTranslation {
    static var isAvailable: Bool {
        if #available(iOS 18, *) { return true }
        return false
    }
}

extension View {
    /// 掛在畫面上：`batch` 變成新值時就翻譯，結果由 onResult 回傳（id → 中文）。
    func appleTranslation(
        batch: TranslationBatch?,
        onResult: @escaping ([String: String]) -> Void,
        onError: @escaping (UserFacingError) -> Void
    ) -> some View {
        modifier(TranslationSupportModifier(batch: batch, onResult: onResult, onError: onError))
    }
}

private struct TranslationSupportModifier: ViewModifier {
    let batch: TranslationBatch?
    let onResult: ([String: String]) -> Void
    let onError: (UserFacingError) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.modifier(AppleTranslationModifier(batch: batch, onResult: onResult, onError: onError))
        } else {
            content.onChange(of: batch) { _, newValue in
                if newValue != nil {
                    onError(UserFacingError(title: "需要 iOS 18 才能離線翻譯", message: "請更新 iPhone 系統，或自己輸入中文。", isRetryable: false))
                }
            }
        }
    }
}

@available(iOS 18, *)
private struct AppleTranslationModifier: ViewModifier {
    let batch: TranslationBatch?
    let onResult: ([String: String]) -> Void
    let onError: (UserFacingError) -> Void

    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .onChange(of: batch) { _, newValue in
                guard newValue != nil else { return }
                if configuration == nil {
                    configuration = TranslationSession.Configuration(
                        source: Locale.Language(identifier: "ja"),
                        target: Locale.Language(identifier: "zh-Hant")
                    )
                } else {
                    configuration?.invalidate()
                }
            }
            .translationTask(configuration) { session in
                guard let batch else { return }
                do {
                    let requests = batch.entries.map {
                        TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.id)
                    }
                    let responses = try await session.translations(from: requests)
                    var result: [String: String] = [:]
                    for response in responses {
                        if let id = response.clientIdentifier {
                            result[id] = response.targetText
                        }
                    }
                    onResult(result)
                } catch {
                    onError(UserFacingError(
                        title: "翻譯沒有成功",
                        message: "如果是第一次使用，請在跳出的視窗按「下載」語言包，再按一次翻譯。"
                    ))
                }
            }
    }
}
