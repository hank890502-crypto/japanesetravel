import CoreGraphics
import Foundation

/// 把 OCR 的文字塊整理成「菜 + 價格」。
///
/// 核心策略是「以價格為錨點」：菜單上幾乎每道菜都有價格，所以
/// 1. 找出所有價格塊（或行尾帶價格的文字塊）
/// 2. 每個價格去找同一列、左邊最近的文字當品名（找不到再找正上方）
/// 3. 剩下沒配到價格的文字（店名、分類、說明）另外列出，讓使用者決定要不要加入
///
/// 這樣多欄排版、價格與品名被拆成兩塊、雜訊多的菜單都能得到可用的結果。
/// 座標為 Vision 正規化座標（左下原點，0–1）。
enum MenuLayoutAnalyzer {
    typealias Candidate = MenuCandidate
    typealias Result = MenuParseResult

    private enum Kind {
        case complete(name: String, price: Decimal)
        case priceOnly(Decimal)
        case text(String)
    }

    private struct Classified {
        let block: RecognizedTextBlock
        let kind: Kind
    }

    static func analyze(_ blocks: [RecognizedTextBlock]) -> Result {
        let classified = blocks.compactMap { block -> Classified? in
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !isJunk(text) else { return nil }
            if let price = PriceParser.priceOnly(text) {
                return Classified(block: block, kind: .priceOnly(price))
            }
            let (name, price) = PriceParser.split(text)
            if let price, !name.isEmpty, name != text {
                return Classified(block: block, kind: .complete(name: name, price: price))
            }
            return Classified(block: block, kind: .text(name.isEmpty ? text : name))
        }

        var items: [Candidate] = []
        var textBlocks = classified.filter { if case .text = $0.kind { return true } else { return false } }
        var usedText = Set<UUID>()

        // 1. 本身就完整的行
        for entry in classified {
            if case .complete(let name, let price) = entry.kind {
                items.append(Candidate(name: name, price: price, confidence: entry.block.confidence, sourceText: entry.block.text, box: entry.block.boundingBox))
            }
        }

        // 2. 獨立的價格塊 → 配對品名
        let priceBlocks = classified.compactMap { entry -> (RecognizedTextBlock, Decimal)? in
            if case .priceOnly(let price) = entry.kind { return (entry.block, price) }
            return nil
        }
        // 由上到下處理，讓上面的價格先挑
        for (priceBlock, price) in priceBlocks.sorted(by: { $0.0.boundingBox.midY > $1.0.boundingBox.midY }) {
            let available = textBlocks.filter { !usedText.contains($0.block.id) }
            if let partner = bestPartner(for: priceBlock, among: available.map(\.block)) {
                usedText.insert(partner.id)
                let name = textName(for: partner, in: textBlocks)
                items.append(Candidate(
                    name: name,
                    price: price,
                    confidence: min(priceBlock.confidence, partner.confidence),
                    sourceText: "\(partner.text) \(priceBlock.text)",
                    box: partner.boundingBox.union(priceBlock.boundingBox)
                ))
            } else {
                // 沒有品名的價格，保留在其他文字裡
                textBlocks.append(Classified(block: priceBlock, kind: .text(priceBlock.text)))
            }
        }

        let others = textBlocks
            .filter { !usedText.contains($0.block.id) }
            .map { entry -> Candidate in
                let name: String
                if case .text(let value) = entry.kind { name = value } else { name = entry.block.text }
                return Candidate(name: name, price: nil, confidence: entry.block.confidence, sourceText: entry.block.text, box: entry.block.boundingBox)
            }

        return Result(items: readingOrder(items), otherLines: topToBottom(others))
    }

    // MARK: - Pairing

    /// 同一列、在價格左邊、最近的文字塊。找不到就找正上方最近的一塊（品名在上、價格在下的排版）。
    private static func bestPartner(for price: RecognizedTextBlock, among texts: [RecognizedTextBlock]) -> RecognizedTextBlock? {
        let pBox = price.boundingBox

        let sameRow = texts.filter { text in
            let tBox = text.boundingBox
            guard verticalOverlapRatio(tBox, pBox) >= 0.4 else { return false }
            let gap = pBox.minX - tBox.maxX
            return gap > -0.03 && gap < 0.6
        }
        if let best = sameRow.min(by: { (pBox.minX - $0.boundingBox.maxX) < (pBox.minX - $1.boundingBox.maxX) }) {
            return best
        }

        let above = texts.filter { text in
            let tBox = text.boundingBox
            let horizontalOverlap = min(tBox.maxX, pBox.maxX + 0.3) - max(tBox.minX, pBox.minX - 0.3)
            guard horizontalOverlap > 0 else { return false }
            let gap = tBox.minY - pBox.maxY
            return gap > -0.005 && gap < max(tBox.height, pBox.height) * 1.5
        }
        return above.min { ($0.boundingBox.minY - pBox.maxY) < ($1.boundingBox.minY - pBox.maxY) }
    }

    private static func verticalOverlapRatio(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        guard overlap > 0 else { return 0 }
        return overlap / max(min(a.height, b.height), 0.0001)
    }

    private static func textName(for block: RecognizedTextBlock, in all: [Classified]) -> String {
        if let entry = all.first(where: { $0.block.id == block.id }), case .text(let name) = entry.kind {
            return name
        }
        return block.text
    }

    // MARK: - Ordering

    /// 由上到下、同一列由左到右。
    private static func topToBottom(_ candidates: [Candidate]) -> [Candidate] {
        candidates.sorted {
            if abs($0.box.midY - $1.box.midY) > min($0.box.height, $1.box.height) * 0.5 {
                return $0.box.midY > $1.box.midY
            }
            return $0.box.minX < $1.box.minX
        }
    }

    /// 依「欄」再「由上到下」排序：先把 minX 分群，欄間距超過 0.2 就視為不同欄。
    private static func readingOrder(_ candidates: [Candidate]) -> [Candidate] {
        guard candidates.count > 1 else { return candidates }
        let byX = candidates.sorted { $0.box.minX < $1.box.minX }
        var columns: [[Candidate]] = []
        var currentColumn: [Candidate] = []
        var currentX: CGFloat = byX[0].box.minX
        for candidate in byX {
            if currentColumn.isEmpty || candidate.box.minX - currentX < 0.2 {
                currentColumn.append(candidate)
            } else {
                columns.append(currentColumn)
                currentColumn = [candidate]
            }
            currentX = candidate.box.minX
        }
        if !currentColumn.isEmpty { columns.append(currentColumn) }
        return columns.flatMap { $0.sorted { $0.box.midY > $1.box.midY } }
    }

    // MARK: - Junk filter

    private static func isJunk(_ text: String) -> Bool {
        let letters = text.filter { $0.isLetter || $0.isNumber }
        if letters.isEmpty { return true }
        if letters.count == 1 && text.count <= 2 { return true }
        return false
    }
}
