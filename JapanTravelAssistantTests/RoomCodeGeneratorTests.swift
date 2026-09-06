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
        #expect(RoomCodeGenerator.isValid("0000"))       // 測試用固定代碼
        #expect(!RoomCodeGenerator.isValid("A8F"))
        #expect(!RoomCodeGenerator.isValid("A8F3K2XYZ"))
        #expect(!RoomCodeGenerator.isValid("A8-3K2"))
    }
}
