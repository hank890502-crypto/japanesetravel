import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 一則對話。
struct ChatMessage: Identifiable, Hashable {
    enum Role { case user, assistant }
    var id = UUID()
    var role: Role
    var text: String
    var isError = false
}

/// 和 Apple 智慧的對話（多輪、有記憶）。角色設定寫死在 App 裡：日本旅遊助手、對長輩說話。
@Observable
@MainActor
final class AssistantChat {
    private(set) var messages: [ChatMessage] = []
    private(set) var isThinking = false
    var availability: AppleIntelligence.Availability { AppleIntelligence.availability }

    /// 常見問題，讓長輩不用打字也能開始
    static let suggestions: [String] = [
        "日本便利商店的便當可以請店員加熱嗎？",
        "藥妝店買藥要注意什麼？",
        "溫泉有刺青可以進去嗎？",
        "日本餐廳要給小費嗎？",
        "退稅要準備什麼？",
        "電車坐錯方向怎麼辦？",
    ]

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    private var session: LanguageModelSession? {
        get { _session as? LanguageModelSession }
        set { _session = newValue }
    }
    #endif
    private var _session: Any?

    /// 模型偶爾還是會用 markdown，顯示前拿掉符號。
    static func plainText(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\*\*|__|`"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^\s*#{1,6}\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^\s*[-*•]\s+"#, with: "・", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func reset() {
        messages = []
        _session = nil
    }

    func send(_ text: String) async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isThinking else { return }
        messages.append(ChatMessage(role: .user, text: question))
        isThinking = true
        defer { isThinking = false }

        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            guard availability.isAvailable else {
                messages.append(ChatMessage(role: .assistant, text: availability.reason ?? "目前無法使用 Apple 智慧。", isError: true))
                return
            }
            if session == nil {
                session = LanguageModelSession(instructions: AppleIntelligence.travelAssistantInstructions)
            }
            do {
                let response = try await session!.respond(to: question)
                messages.append(ChatMessage(role: .assistant, text: Self.plainText(response.content)))
            } catch let error as LanguageModelSession.GenerationError {
                if case .exceededContextWindowSize = error {
                    // 對話太長：重開一段，保留畫面上的紀錄
                    session = LanguageModelSession(instructions: AppleIntelligence.travelAssistantInstructions)
                    if let retry = try? await session!.respond(to: question) {
                        messages.append(ChatMessage(role: .assistant, text: Self.plainText(retry.content)))
                        return
                    }
                }
                messages.append(ChatMessage(role: .assistant, text: AppleIntelligenceAIService.map(error).message, isError: true))
            } catch {
                messages.append(ChatMessage(role: .assistant, text: "剛才沒有回應，請再問一次。", isError: true))
            }
            return
        }
        #endif
        messages.append(ChatMessage(role: .assistant, text: availability.reason ?? "需要 iOS 26 以上才能使用 Apple 智慧。", isError: true))
    }
}
