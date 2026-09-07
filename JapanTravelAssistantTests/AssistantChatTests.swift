import Testing
@testable import JapanTravelAssistant

/// 「我想問問題」的對話邏輯（不呼叫真正的模型）。
@Suite("我想問問題")
@MainActor
struct AssistantChatTests {
    @Test("這台裝置不能用 Apple 智慧時：送出不會被接受，也不會多出任何泡泡")
    func unavailableDoesNotAppendMessages() async {
        let chat = AssistantChat(availabilityOverride: .init(isAvailable: false, reason: "需要 iOS 26 以上才能使用 Apple 智慧。"))
        let accepted = await chat.send("日本餐廳要給小費嗎？")
        #expect(!accepted)
        #expect(chat.messages.isEmpty)
        #expect(!chat.isThinking)
        #expect(chat.availability.reason == "需要 iOS 26 以上才能使用 Apple 智慧。")
    }

    @Test("空白問題不會被接受")
    func blankIsRejected() async {
        let chat = AssistantChat(availabilityOverride: .init(isAvailable: true, reason: nil))
        let accepted = await chat.send("   \n ")
        #expect(!accepted)
        #expect(chat.messages.isEmpty)
    }

    @Test("常見問題清單不是空的，而且每一題都是完整的問句")
    func suggestionsExist() {
        #expect(AssistantChat.suggestions.count >= 4)
        #expect(AssistantChat.suggestions.allSatisfy { $0.hasSuffix("？") })
    }

    @Test("回答裡的 markdown 符號會被拿掉")
    func plainText() {
        let text = AssistantChat.plainText("## 結論\n**可以**，請店員加熱。\n- 先說 温めてください\n")
        #expect(text == "結論\n可以，請店員加熱。\n・先說 温めてください")
    }
}
