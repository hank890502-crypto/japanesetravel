import Foundation

/// 用 iOS 內建的日文斷詞器產生讀音，完全離線、不需要 API。
/// 漢字 → 羅馬拼音（例如 唐揚げ → karaage），再轉成平假名（からあげ）。
/// 專有名詞或少見寫法可能不準，ChatGPT 給的拼音會優先使用。
enum JapaneseReading {
    static func romaji(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, containsJapanese(trimmed) else { return nil }

        let cfString = trimmed as CFString
        let range = CFRange(location: 0, length: CFStringGetLength(cfString))
        let locale = Locale(identifier: "ja") as CFLocale
        guard let tokenizer = CFStringTokenizerCreate(nil, cfString, range, kCFStringTokenizerUnitWordBoundary, locale) else { return nil }

        var parts: [String] = []
        var tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        while !tokenType.isEmpty {
            let tokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let original = CFStringCreateWithSubstring(nil, cfString, tokenRange) as String? ?? ""
            if let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String,
               !latin.isEmpty {
                parts.append(latin)
            } else if original.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) {
                parts.append(original)   // 英文字、數字照抄
            }
            tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }
        let joined = parts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? nil : joined
    }

    static func hiragana(for text: String) -> String? {
        guard let romaji = romaji(for: text) else { return nil }
        return romaji.applyingTransform(.latinToHiragana, reverse: false)
    }

    static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value)
        }
    }
}
