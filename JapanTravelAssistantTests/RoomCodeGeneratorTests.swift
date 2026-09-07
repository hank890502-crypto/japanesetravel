import Testing
@testable import JapanTravelAssistant

@Suite("房間代碼")
struct RoomCodeGeneratorTests {
    @Test("產生的代碼永遠合法")
    func generatedCodesAreValid() {
        for _ in 0..<200 {
            let code = RoomCodeGenerator.generate()
            #expect(code.count == 6)
            #expect(RoomCodeGenerator.isValid(code))
            #expect(!code.contains("0") && !code.contains("O") && !code.contains("1") && !code.contains("I"))
        }
    }

    @Test("使用者輸入會被清理")
    func normalizeStripsAndUppercases() {
        #expect(RoomCodeGenerator.normalize(" a8f-3k2 ") == "A8F3K2")
        #expect(RoomCodeGenerator.isValid(RoomCodeGenerator.normalize("a8f 3k2")))
        #expect(RoomCodeGenerator.isValid("0000"))       // 舊連結可能只有 4 碼，仍接受
        #expect(!RoomCodeGenerator.isValid("A8F"))
        #expect(!RoomCodeGenerator.isValid("A8F3K2XYZ"))
        #expect(!RoomCodeGenerator.isValid("A8-3K2"))
    }

    @Test("LINE 或注音鍵盤打出的全形英數會折成半形；全形字元本身不算合法代碼")
    func normalizeFoldsFullwidth() {
        #expect(RoomCodeGenerator.normalize("Ａ８Ｆ３Ｋ２") == "A8F3K2")
        #expect(RoomCodeGenerator.normalize("ａ８ｆ３ｋ２") == "A8F3K2")
        #expect(RoomCodeGenerator.normalize("Ａ８Ｆ　３Ｋ２") == "A8F3K2")   // 全形空白也去掉
        #expect(RoomCodeGenerator.isValid(RoomCodeGenerator.normalize("Ａ８Ｆ３Ｋ２")))
        #expect(!RoomCodeGenerator.isValid("Ａ８Ｆ３Ｋ２"))
        #expect(!RoomCodeGenerator.isValid("A8F3K中"))
    }
}
