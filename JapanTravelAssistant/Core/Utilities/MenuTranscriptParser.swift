import Foundation

/// 把 Live Text 依「閱讀順序」輸出的文字行，整理成「菜 + 價格」。
///
/// Live Text 的閱讀順序對直排、橫排、圖片式排版都是「品名 → 價格 → 品名 → 價格」，
/// 所以規則很單純：
/// 1. 有價格的行：價格配給「前面最近的一行日文品名」；括號行併入它上一行。
/// 2. 沒價格的行：日文就先記著等價格；英文／韓文／簡中翻譯行直接略過。
/// 3. 一行裡有多個價格（兩欄被讀成一行）：依價格切成多道菜。
/// 4. 等不到價格的日文行（店名、分類、說明）→ 其他文字。
enum MenuTranscriptParser {
    static func parse(lines: [String], confidence: Double = 0.9) -> MenuParseResult {
        var items: [MenuCandidate] = []
        var others: [MenuCandidate] = []
        var pending: [String] = []          // 等價格的日文行（最多留兩行）
        var noteDepth = 0                   // 跨行括號（說明文字）尚未關閉
        var previousWasForeign = false
        var currentSection: String?         // 最近看到的分類標題
        var currentSectionRaw = ""
        var sectionHasItems = false

        func flushPending(keepLast: Int) {
            while pending.count > keepLast {
                let line = pending.removeFirst()
                others.append(MenuCandidate(name: line, price: nil, confidence: confidence, sourceText: line))
            }
        }

        for raw in lines {
            let line = PriceParser.normalize(raw)
            if line.isEmpty {
                // 空行 = 區塊結束：還在等價格的行就不會是菜
                flushPending(keepLast: 0)
                continue
            }
            guard !isJunk(line) else { continue }

            // 跨行的括號說明：直到括號關閉都當作說明，不當品名
            if noteDepth > 0 {
                if line.contains(")") || line.contains("）") { noteDepth = 0 }
                continue
            }

            let segments = PriceParser.splitAll(line)
            let hasPrice = segments.contains { $0.price != nil }

            if hasPrice {
                for segment in segments {
                    guard let price = segment.price else {
                        // 沒價格的尾段 → 當下一道菜的品名候選
                        if !segment.name.isEmpty { pending.append(segment.name) }
                        continue
                    }
                    var name = segment.name
                    if name.isEmpty || isNoteLike(name) {
                        // 價格自己一行（或只剩括號）：拿前面的品名
                        if let taken = takePendingName(&pending) {
                            name = name.isEmpty ? taken : "\(taken)\(name)"
                        }
                    }
                    guard !name.isEmpty else {
                        others.append(MenuCandidate(name: PriceFormatter.string(price) ?? line, price: nil, confidence: confidence, sourceText: raw))
                        continue
                    }
                    items.append(MenuCandidate(name: name, price: price, confidence: confidence, sourceText: raw, section: currentSection))
                    sectionHasItems = true
                }
                flushPending(keepLast: 0)
                previousWasForeign = false
                continue
            }

            // 沒有價格
            if isForeignTranslation(line, previousWasForeign: previousWasForeign) {
                previousWasForeign = true
                continue
            }
            previousWasForeign = false

            if isOpeningNote(line) {
                noteDepth = 1
                continue
            }

            let name = PriceParser.cleanName(line)
            guard !name.isEmpty else { continue }

            if isSectionHeader(name) {
                flushPending(keepLast: 0)
                if let previous = currentSection, !sectionHasItems {
                    // 兩個標題連在一起、中間沒有菜（多欄排版）：分不出哪道菜屬於哪一欄，兩個都不套用
                    others.append(MenuCandidate(name: previous, price: nil, confidence: confidence, sourceText: currentSectionRaw))
                    others.append(MenuCandidate(name: name, price: nil, confidence: confidence, sourceText: raw))
                    currentSection = nil
                    currentSectionRaw = ""
                    sectionHasItems = false
                    continue
                }
                currentSection = name.replacingOccurrences(of: " ", with: "")
                currentSectionRaw = raw
                sectionHasItems = false
                continue
            }
            if isRemark(name) {
                flushPending(keepLast: 0)
                others.append(MenuCandidate(name: name, price: nil, confidence: confidence, sourceText: raw))
                continue
            }

            pending.append(name)
            flushPending(keepLast: 2)
        }
        flushPending(keepLast: 0)

        return MenuParseResult(items: items, otherLines: others)
    }

    // MARK: - Helpers

    /// 取出品名：最後一行；以下情況跟上一行合併成一個品名：
    /// - 最後一行是括號補充：豚軟骨うま煮 + （パイカ）
    /// - 上一行以「の／と／・」結尾：小海老の + 唐揚げ
    /// - 上一行很短（≤3 字）：藁焼き + かつおたたき、お刺身 + 五種盛り
    private static func takePendingName(_ pending: inout [String]) -> String? {
        guard let last = pending.popLast() else { return nil }
        defer { pending.removeAll() }
        guard let previous = pending.last else { return last }
        if isNoteLike(last) || endsWithConnector(previous) || previous.count <= 3 {
            return "\(previous)\(last)"
        }
        return last
    }

    private static func endsWithConnector(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return "のと・、".contains(last)
    }

    /// 常見的分類標題：不會是菜，直接進其他文字，也不會被併進品名。
    private static let sectionHeaders: Set<String> = [
        "揚げ物", "揚物", "焼き物", "焼物", "煮物", "軽食", "単品", "一品", "一品料理", "その他",
        "ドリンク", "ソフトドリンク", "ワイン", "サワー", "焼酎", "日本酒", "ビール", "麺類", "麺", "ご飯もの", "ご飯",
        "デザート", "サラダ", "鍋", "串焼き", "串焼", "定食", "丼", "丼物",
        "おすすめ", "本日のおすすめ", "新登場", "季節限定", "限定", "おつまみ", "つまみ", "アルコール", "メニュー",
        "前菜", "冷菜", "温菜", "肉料理", "魚料理", "野菜料理", "揚げ物・焼き物", "御飯", "ごはん", "ライス", "汁物", "スープ",
        "ハイボール", "カクテル", "梅酒", "果実酒", "ノンアルコール", "ドリンクメニュー", "フードメニュー", "定食メニュー", "セット",
        "寿司", "にぎり", "握り", "巻物", "天ぷら", "うどん", "そば", "ラーメン", "麺類", "甘味", "スイーツ", "お子様", "お子様メニュー",
    ]

    private static func isSectionHeader(_ text: String) -> Bool {
        sectionHeaders.contains(text.replacingOccurrences(of: " ", with: ""))
    }

    /// ※ ☆ ★ 開頭的說明文字
    private static func isRemark(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        return "※☆★●○◎▲■□".contains(first)
    }

    /// 「（パイカ）」「(大)」這種只有括號的補充說明
    private static func isNoteLike(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.range(of: #"^[（(][^）)]*[）)]$"#, options: .regularExpression) != nil
    }

    /// 以括號開頭但沒關閉：跨行的說明文字
    private static func isOpeningNote(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("(") || trimmed.hasPrefix("（") else { return false }
        return !(trimmed.contains(")") || trimmed.contains("）"))
    }

    /// 英文／韓文行，或緊接在英文後面的「只有漢字」行（通常是簡中翻譯）→ 略過
    private static func isForeignTranslation(_ text: String, previousWasForeign: Bool) -> Bool {
        let scalars = text.unicodeScalars
        let hasKana = scalars.contains { (0x3040...0x30FF).contains($0.value) || (0x31F0...0x31FF).contains($0.value) }
        let hasKanji = scalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
        let hasHangul = scalars.contains { (0xAC00...0xD7AF).contains($0.value) || (0x1100...0x11FF).contains($0.value) }
        let hasLatin = scalars.contains { (0x41...0x5A).contains($0.value) || (0x61...0x7A).contains($0.value) }

        if hasHangul { return true }
        if hasKana { return false }
        if hasLatin && !hasKanji { return true }              // 純英文
        if hasKanji && !hasKana && previousWasForeign { return true } // 英文後面的中文翻譯
        return false
    }

    private static func isJunk(_ text: String) -> Bool {
        let meaningful = text.filter { $0.isLetter || $0.isNumber }
        if meaningful.isEmpty { return true }
        if meaningful.count == 1 && text.count <= 2 { return true }
        if text == "円" { return true }
        return false
    }
}
