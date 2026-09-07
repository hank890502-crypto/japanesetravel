import Foundation

/// 把 Live Text 依「閱讀順序」輸出的文字行，整理成「菜 + 價格」。
///
/// Live Text 的閱讀順序對直排、橫排、圖片式排版都是「品名 → 價格 → 品名 → 價格」，
/// 所以規則很單純：
/// 1. 有價格的行：價格配給「前面最近的一行日文品名」；括號行併入它上一行。
/// 2. 沒價格的行：日文就先記著等價格；英文／韓文／簡中翻譯行直接略過。
/// 3. 一行裡有多個價格（兩欄被讀成一行）：依價格切成多道菜。
/// 4. 等不到價格的日文行（店名、分類、說明）→ 其他文字。
/// 5. 「並 600円」「大 800円」這種尺寸行：品名是上一行的菜 + 尺寸。
/// 6. 先一整欄品名、再一整欄價格（橫排、間距大）：先依序配對再解析。
enum MenuTranscriptParser {
    /// 跨行括號說明最多跳過幾行；超過就當 OCR 漏了右括號，照常解析。
    private static let maxNoteLines = 3
    /// 連續幾個「只有價格」的行才視為「價格一欄」
    private static let minimumColumnRun = 3

    static func parse(lines rawLines: [String], confidence: Double = 0.9) -> MenuParseResult {
        let lines = interleaveColumns(rawLines)
        var items: [MenuCandidate] = []
        var others: [MenuCandidate] = []
        var pending: [String] = []          // 等價格的日文行（最多留兩行）
        var noteDepth = 0                   // 跨行括號（說明文字）尚未關閉
        var noteLinesSkipped = 0
        var previousWasForeign = false
        var currentSection: String?         // 最近看到的分類標題
        var previousSection: String?
        var currentSectionRaw = ""
        var sectionHasItems = false
        var sectionSetByPreviousLine = false
        var sizeBase: String?               // 「カレー」→「並 600円」「大 800円」：尺寸行共用的品名
        var pendingSize: String?            // 尺寸自己一行（「並」→「600円」）

        func flushPending(keepLast: Int) {
            while pending.count > keepLast {
                let line = pending.removeFirst()
                others.append(MenuCandidate(name: line, price: nil, confidence: confidence, sourceText: line))
            }
        }

        for (index, raw) in lines.enumerated() {
            var line = PriceParser.normalize(raw)
            if line.isEmpty {
                // 空行 = 區塊結束：還在等價格的行就不會是菜
                flushPending(keepLast: 0)
                sizeBase = nil
                pendingSize = nil
                continue
            }
            guard !isJunk(line) else { continue }
            let sectionWasJustSet = sectionSetByPreviousLine
            sectionSetByPreviousLine = false

            // 跨行的括號說明：直到括號關閉都當作說明，不當品名。
            // 但一出現價格就結束說明（OCR 常漏讀右括號，不能把後面整份菜單都吃掉），跳過的行數也有上限。
            if noteDepth > 0 {
                let closes = line.contains(")") || line.contains("）")
                let priced = PriceParser.splitAll(line).contains { $0.price != nil }
                if priced {
                    noteDepth = 0
                    line = line.replacingOccurrences(of: #"^[^）)]*[）)]"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                    if line.isEmpty { continue }
                } else if closes {
                    noteDepth = 0
                    continue
                } else if noteLinesSkipped >= maxNoteLines {
                    noteDepth = 0
                } else {
                    noteLinesSkipped += 1
                    continue
                }
            }

            // ※ 開頭的備註（「※表示価格は税込（消費税10%）です」）就算含數字也不是菜
            if isRemark(line) {
                flushPending(keepLast: 0)
                sizeBase = nil
                pendingSize = nil
                others.append(MenuCandidate(name: PriceParser.cleanName(line), price: nil, confidence: confidence, sourceText: raw))
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
                    var name = stripBullet(segment.name)
                    if let size = sizeWord(in: name) ?? (name.isEmpty ? pendingSize : nil) {
                        // 尺寸行：「並 600円」「大 800円」→ 上一行的菜 + 尺寸，且同一道菜的尺寸行共用品名
                        if sizeBase == nil { sizeBase = takePendingName(&pending) }
                        if let base = sizeBase { name = "\(base)（\(size)）" }
                    } else {
                        sizeBase = nil
                        if name.isEmpty || isNoteLike(name) {
                            // 價格自己一行（或只剩括號）：拿前面的品名
                            if let taken = takePendingName(&pending) {
                                name = name.isEmpty ? taken : "\(taken)\(name)"
                            } else if name.isEmpty, sectionWasJustSet, !sectionHasItems,
                                      let section = currentSection, ambiguousSectionHeaders.contains(section) {
                                // 「ラーメン」這種也可能是菜名的分類詞，緊接著就是價格：它其實是一道菜
                                name = section
                                currentSection = previousSection
                            }
                        }
                    }
                    pendingSize = nil
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
                noteLinesSkipped = 0
                continue
            }

            let name = PriceParser.cleanName(line)
            guard !name.isEmpty else { continue }

            // 尺寸自己一行（直排：「並」下一行「600円」）；前面沒有菜可以掛就略過
            if let size = sizeWord(in: name) {
                if !pending.isEmpty || sizeBase != nil { pendingSize = size }
                continue
            }

            // 分類標題。「ラーメン」「ビール」這種也可能是菜名的詞，後面直接接價格行時是一道菜，不是分類。
            if isSectionHeader(name), !(ambiguousSectionHeaders.contains(compact(name)) && nextLineBelongsToDish(lines, after: index)) {
                flushPending(keepLast: 0)
                sizeBase = nil
                pendingSize = nil
                if let previous = currentSection, !sectionHasItems {
                    // 兩個標題連在一起、中間沒有菜（多欄排版）：分不出哪道菜屬於哪一欄，兩個都不套用
                    others.append(MenuCandidate(name: previous, price: nil, confidence: confidence, sourceText: currentSectionRaw))
                    others.append(MenuCandidate(name: name, price: nil, confidence: confidence, sourceText: raw))
                    currentSection = nil
                    previousSection = nil
                    currentSectionRaw = ""
                    sectionHasItems = false
                    continue
                }
                previousSection = currentSection
                currentSection = compact(name)
                currentSectionRaw = raw
                sectionHasItems = false
                sectionSetByPreviousLine = true
                continue
            }
            if isBulletNote(name) {
                flushPending(keepLast: 0)
                sizeBase = nil
                pendingSize = nil
                others.append(MenuCandidate(name: name, price: nil, confidence: confidence, sourceText: raw))
                continue
            }

            sizeBase = nil
            pendingSize = nil
            pending.append(name)
            flushPending(keepLast: 2)
        }
        flushPending(keepLast: 0)

        return MenuParseResult(items: items, otherLines: others)
    }

    // MARK: - 欄式閱讀順序

    /// 橫排菜單品名靠左、價格靠右且間距大時，Live Text 常先輸出整欄品名再輸出整欄價格：
    /// ["若どり唐揚げ", "手羽先", "味噌串カツ", "¥540", "¥430", "¥540"]。
    /// 連續 3 個以上「只有價格」的行，前面剛好有夠多連續的日文品名行時，依序一一配對改成交錯順序。
    static func interleaveColumns(_ lines: [String]) -> [String] {
        var output: [String] = []
        var index = 0
        while index < lines.count {
            var end = index
            while end < lines.count, isPriceOnlyLine(lines[end]) { end += 1 }
            let priceRun = end - index
            if priceRun >= minimumColumnRun {
                var nameStart = output.count
                while nameStart > 0, isNameLikeLine(output[nameStart - 1]) { nameStart -= 1 }
                if output.count - nameStart >= priceRun {
                    let names = Array(output.suffix(priceRun))
                    output.removeLast(priceRun)
                    for (name, price) in zip(names, lines[index..<end]) {
                        output.append(name)
                        output.append(price)
                    }
                    index = end
                    continue
                }
            }
            output.append(lines[index])
            index += 1
        }
        return output
    }

    private static func isPriceOnlyLine(_ raw: String) -> Bool {
        let line = PriceParser.normalize(raw)
        guard !line.isEmpty, !isJunk(line) else { return false }
        return PriceParser.priceOnly(line) != nil
    }

    /// 看起來是一道菜的品名：日文、沒價格、不是分類／備註／翻譯／括號說明／尺寸
    private static func isNameLikeLine(_ raw: String) -> Bool {
        let line = PriceParser.normalize(raw)
        guard !line.isEmpty, !isJunk(line), !isRemark(line) else { return false }
        guard !PriceParser.splitAll(line).contains(where: { $0.price != nil }) else { return false }
        if isForeignTranslation(line, previousWasForeign: false) || isOpeningNote(line) || isNoteLike(line) { return false }
        let name = PriceParser.cleanName(line)
        guard !name.isEmpty, !isBulletNote(name), sizeWord(in: name) == nil else { return false }
        return !pureSectionHeaders.contains(compact(name))
    }

    /// 下一行是「這道菜的價格」：只有價格（800円）、尺寸加價格（並 800円）、
    /// 或尺寸自己一行再接價格（並／800円）。下一行是另一個品名或「品名 價格」就不是。
    private static func nextLineBelongsToDish(_ lines: [String], after index: Int) -> Bool {
        var next = index + 1
        guard next < lines.count else { return false }
        var line = PriceParser.normalize(lines[next])
        if sizeWord(in: PriceParser.cleanName(line)) != nil, !PriceParser.splitAll(line).contains(where: { $0.price != nil }) {
            next += 1
            guard next < lines.count else { return false }
            line = PriceParser.normalize(lines[next])
        }
        guard let priced = PriceParser.splitAll(line).first(where: { $0.price != nil }) else { return false }
        return priced.name.isEmpty || isNoteLike(priced.name) || sizeWord(in: priced.name) != nil
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

    private static func compact(_ text: String) -> String {
        text.replacingOccurrences(of: " ", with: "")
    }

    /// 純分類詞：本身不會是一道菜，直接進其他文字，也不會被併進品名。
    static let pureSectionHeaders: Set<String> = [
        "揚げ物", "揚物", "焼き物", "焼物", "煮物", "軽食", "単品", "一品", "一品料理", "その他",
        "ドリンク", "ソフトドリンク", "麺類", "ご飯もの",
        "デザート", "丼物",
        "おすすめ", "本日のおすすめ", "新登場", "季節限定", "限定", "おつまみ", "つまみ", "アルコール", "メニュー",
        "前菜", "冷菜", "温菜", "肉料理", "魚料理", "野菜料理", "揚げ物・焼き物", "汁物",
        "果実酒", "ノンアルコール", "ドリンクメニュー", "フードメニュー", "定食メニュー",
        "甘味", "スイーツ", "お子様", "お子様メニュー",
    ]

    /// 也可能是菜名的分類詞（拉麵店的「ラーメン」、居酒屋的「ビール」「ライス」）：
    /// 後面接的是「沒價格的日文行」才當分類；後面直接接價格行就是一道菜。
    static let ambiguousSectionHeaders: Set<String> = [
        "ワイン", "サワー", "焼酎", "日本酒", "ビール", "麺", "ご飯", "御飯", "ごはん", "ライス",
        "サラダ", "鍋", "串焼き", "串焼", "定食", "丼", "スープ",
        "ハイボール", "カクテル", "梅酒", "セット",
        "寿司", "にぎり", "握り", "巻物", "天ぷら", "うどん", "そば", "ラーメン",
    ]

    /// 所有分類標題（純分類 + 可能是菜名的分類詞）
    static let sectionHeaders: Set<String> = pureSectionHeaders.union(ambiguousSectionHeaders)

    static func isSectionHeader(_ text: String) -> Bool {
        sectionHeaders.contains(compact(text))
    }

    /// 尺寸／份量詞：並、大、中、小、大盛り、ハーフ、S/M/L…
    static let sizeWords: Set<String> = [
        "並", "大", "中", "小", "特大", "並盛", "並盛り", "大盛", "大盛り", "中盛", "中盛り", "小盛", "小盛り", "特盛", "特盛り",
        "ハーフ", "レギュラー", "ラージ", "スモール", "ミニ", "S", "M", "L", "LL", "SS",
    ]

    /// 這段品名去掉括號後只剩尺寸詞時回傳該詞（「並」「(大)」「大盛り」）。
    static func sizeWord(in name: String) -> String? {
        let trimmed = name
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"^[（(]\s*|\s*[）)]$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let key = trimmed.uppercased()
        return sizeWords.contains(key) ? key : nil
    }

    /// ※ 開頭的備註：就算含數字（消費税10%、11:30〜）也不是菜
    private static func isRemark(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).hasPrefix("※")
    }

    /// ☆ ★ ● ○ 開頭、沒有價格的說明文字
    private static func isBulletNote(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        return "※☆★●○◎▲■□".contains(first)
    }

    /// 有價格的行：品名前面的 ★ ● 這類記號拿掉（★人気 若どり唐揚げ 540円）
    private static func stripBullet(_ name: String) -> String {
        let stripped = name.replacingOccurrences(of: #"^[☆★●○◎▲■□]\s*"#, with: "", options: .regularExpression)
        return stripped.isEmpty ? name : stripped
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
        if sizeWords.contains(text) { return false }
        let meaningful = text.filter { $0.isLetter || $0.isNumber }
        if meaningful.isEmpty { return true }
        if meaningful.count == 1 && text.count <= 2 { return true }
        if text == "円" { return true }
        return false
    }
}
