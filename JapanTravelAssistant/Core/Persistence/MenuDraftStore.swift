import Foundation
import Observation
import UIKit

/// 目前正在編輯的菜單草稿。存成 JSON 放在 App 的 Documents，App 被關掉也不會不見。
/// 原始照片只留在記憶體（不落地）。
@Observable
@MainActor
final class MenuDraftStore {
    var draft: MenuDraft? {
        didSet { persist() }
    }
    var sourceImages: [UIImage] = []

    private let fileURL: URL?

    init(directory: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first) {
        fileURL = directory?.appendingPathComponent("menu-draft.json")
        draft = Self.load(from: fileURL)
    }

    func startNew(items: [MenuItemDraft] = [], otherLines: [MenuItemDraft] = [], images: [UIImage] = []) {
        draft = MenuDraft(items: items, otherLines: otherLines)
        sourceImages = images
    }

    /// 把新拍的一面菜單加進目前的草稿（例如先拍正面、改好後再拍背面）。
    /// 日文名和現有的菜相同的不重複加；照片接在後面。沒有草稿就等同 startNew。
    func append(items: [MenuItemDraft], otherLines: [MenuItemDraft], images: [UIImage]) {
        guard var current = draft else {
            startNew(items: items, otherLines: otherLines, images: images)
            return
        }
        var known = Set(current.items.map(\.normalizedJapaneseName))
        for item in items where !known.contains(item.normalizedJapaneseName) {
            current.items.append(item)
            known.insert(item.normalizedJapaneseName)
        }
        var knownOthers = Set(current.otherLines.map(\.normalizedJapaneseName))
        for line in otherLines where !known.contains(line.normalizedJapaneseName) && !knownOthers.contains(line.normalizedJapaneseName) {
            current.otherLines.append(line)
            knownOthers.insert(line.normalizedJapaneseName)
        }
        draft = current
        sourceImages += images
    }

    func clear() {
        draft = nil
        sourceImages = []
    }

    /// 把「其他文字」裡的一行正式變成一道菜。畫面上是「加入」→ 編輯 → 儲存之後才呼叫；
    /// 使用者在編輯畫面按「取消」時什麼都不會動，那一行仍留在其他文字裡。
    func promoteOtherLine(_ item: MenuItemDraft) {
        guard var current = draft else {
            draft = MenuDraft(items: [item])
            return
        }
        current.otherLines.removeAll { $0.id == item.id }
        if let index = current.items.firstIndex(where: { $0.id == item.id }) {
            current.items[index] = item
        } else {
            current.items.append(item)
        }
        draft = current
    }

    struct ImportSummary: Hashable {
        var updated: Int
        var added: Int
        var total: Int { updated + added }
    }

    /// 合併時怎麼對待使用者已經填好的欄位
    enum MergeMode: Sendable {
        /// 匯入的資料優先：有中文就換中文、有價格就換價格、有選項就整組取代（ChatGPT「補進目前的菜單」）
        case overwrite
        /// 只填「目前是空的」欄位：使用者改過的日文、中文、價格、分類、選項都保留（AI 整理「補進去」）
        case fillMissing
    }

    /// 用 ChatGPT 匯入的項目「取代」目前的菜單（從零建立一份新的）。
    /// - Parameter keepingImages: true 時保留原始照片（AI 整理的是同一批照片）。
    @discardableResult
    func replace(with imported: [MenuImportParser.ImportedItem], keepingImages: Bool = false) -> ImportSummary {
        let items = imported
            .filter { !$0.japaneseName.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { item in
                MenuItemDraft(
                    japaneseName: item.japaneseName,
                    chineseName: item.chineseName,
                    priceText: item.price.map { "\($0)" } ?? "",
                    sectionName: item.section,
                    note: item.note,
                    options: Self.optionDrafts(from: item.options),
                    reading: item.reading
                )
            }
        var chinese: [String: String] = [:]
        for item in imported {
            if let section = item.section?.nilIfBlank, let zh = item.sectionChinese?.nilIfBlank { chinese[section] = zh }
        }
        draft = MenuDraft(restaurantName: keepingImages ? (draft?.restaurantName ?? "") : "", items: items, sectionChineseNames: chinese)
        if !keepingImages { sourceImages = [] }
        return ImportSummary(updated: 0, added: items.count)
    }

    /// 把 ChatGPT／AI 整理的項目合併進目前的菜單：
    /// 日文名稱對得上的 → 更新；對不上的 → 新增。沒有草稿就直接建立。
    ///
    /// 配對分兩輪：先找日文名完全相同的，再找互為子字串的（OCR 漏字：「手先」對「手羽先」），
    /// 子字串配對挑現有名稱最長的那道，且每道菜只會被配到一次，
    /// 這樣草稿裡同時有「唐揚げ」和「若どり唐揚げ」時不會兩筆都更新到同一道。
    /// 日文名只在完全相同時才用匯入的（子字串配對保留使用者現有的寫法）。
    @discardableResult
    func merge(imported: [MenuImportParser.ImportedItem], mode: MergeMode = .overwrite) -> ImportSummary {
        var current = draft ?? MenuDraft()
        var updated = 0
        var added = 0

        let keys = imported.map { PriceParser.normalize($0.japaneseName).replacingOccurrences(of: " ", with: "") }
        let existingKeys = current.items.map(\.normalizedJapaneseName)
        var assignment: [Int: (index: Int, exact: Bool)] = [:]
        var used = Set<Int>()

        // 第一輪：完全相同
        for (importedIndex, key) in keys.enumerated() where !key.isEmpty {
            if let index = existingKeys.indices.first(where: { !used.contains($0) && existingKeys[$0] == key }) {
                assignment[importedIndex] = (index, true)
                used.insert(index)
            }
        }
        // 第二輪：互為子字串（≥3 字），挑現有名稱最長的
        for (importedIndex, key) in keys.enumerated() where !key.isEmpty && assignment[importedIndex] == nil {
            let candidates = existingKeys.indices.filter { index in
                guard !used.contains(index) else { return false }
                let existingKey = existingKeys[index]
                return (existingKey.count >= 3 && key.contains(existingKey)) || (key.count >= 3 && existingKey.contains(key))
            }
            if let index = candidates.max(by: { existingKeys[$0].count < existingKeys[$1].count }) {
                assignment[importedIndex] = (index, false)
                used.insert(index)
            }
        }

        for (importedIndex, item) in imported.enumerated() {
            let key = keys[importedIndex]
            guard !key.isEmpty else { continue }
            if let match = assignment[importedIndex] {
                var existing = current.items[match.index]
                Self.apply(item, to: &existing, exactMatch: match.exact, mode: mode)
                current.items[match.index] = existing
                updated += 1
            } else {
                current.items.append(MenuItemDraft(
                    japaneseName: item.japaneseName,
                    chineseName: item.chineseName,
                    priceText: item.price.map { "\($0)" } ?? "",
                    sectionName: item.section,
                    note: item.note,
                    options: Self.optionDrafts(from: item.options),
                    reading: item.reading
                ))
                added += 1
            }
            if let section = item.section?.nilIfBlank, let zh = item.sectionChinese?.nilIfBlank,
               mode == .overwrite || current.sectionChineseNames[section]?.nilIfBlank == nil {
                current.sectionChineseNames[section] = zh
            }
            // 其他文字裡若有同名的，移除（已經變成菜了）
            current.otherLines.removeAll { $0.normalizedJapaneseName == key }
        }
        draft = current
        return ImportSummary(updated: updated, added: added)
    }

    private static func apply(_ item: MenuImportParser.ImportedItem, to existing: inout MenuItemDraft, exactMatch: Bool, mode: MergeMode) {
        switch mode {
        case .overwrite:
            if exactMatch { existing.japaneseName = item.japaneseName }
            if let chinese = item.chineseName.nilIfBlank { existing.chineseName = chinese }
            if let price = item.price { existing.priceText = "\(price)" }
            if let note = item.note { existing.note = note }
            if let section = item.section { existing.sectionName = section }
            if !item.options.isEmpty { existing.options = optionDrafts(from: item.options) }
            if let reading = item.reading { existing.reading = reading }
        case .fillMissing:
            if existing.chineseName.nilIfBlank == nil, let chinese = item.chineseName.nilIfBlank { existing.chineseName = chinese }
            if existing.priceText.nilIfBlank == nil, let price = item.price { existing.priceText = "\(price)" }
            if existing.note?.nilIfBlank == nil, let note = item.note?.nilIfBlank { existing.note = note }
            if existing.sectionName?.nilIfBlank == nil, let section = item.section?.nilIfBlank { existing.sectionName = section }
            if existing.options.isEmpty, !item.options.isEmpty { existing.options = optionDrafts(from: item.options) }
            if existing.reading?.nilIfBlank == nil, let reading = item.reading?.nilIfBlank { existing.reading = reading }
        }
    }

    private static func optionDrafts(from imported: [MenuImportParser.ImportedOption]) -> [MenuOptionDraft] {
        imported.map { option in
            MenuOptionDraft(
                groupName: option.groupName,
                japaneseName: option.japaneseName,
                chineseName: option.chineseName,
                priceDeltaText: option.priceDelta == 0 ? "0" : (option.priceDelta > 0 ? "+\(option.priceDelta)" : "\(option.priceDelta)")
            )
        }
    }

    /// 幫還沒有拼音的菜補上 iOS 斷詞器產生的羅馬拼音。
    func fillMissingReadings() {
        guard var current = draft else { return }
        var changed = false
        for index in current.items.indices where current.items[index].reading?.nilIfBlank == nil {
            if let romaji = JapaneseReading.romaji(for: current.items[index].japaneseName) {
                current.items[index].reading = romaji
                changed = true
            }
        }
        if changed { draft = current }
    }

    func setSectionChineseName(_ chinese: String?, for section: String) {
        guard var current = draft else { return }
        current.sectionChineseNames[section] = chinese?.nilIfBlank
        draft = current
    }

    func discardOtherLine(id: UUID) {
        guard var current = draft else { return }
        current.otherLines.removeAll { $0.id == id }
        draft = current
    }

    func upsert(_ item: MenuItemDraft) {
        guard var current = draft else {
            draft = MenuDraft(items: [item])
            return
        }
        if let index = current.items.firstIndex(where: { $0.id == item.id }) {
            current.items[index] = item
        } else {
            current.items.append(item)
        }
        draft = current
    }

    func remove(id: UUID) {
        guard var current = draft else { return }
        current.items.removeAll { $0.id == id }
        draft = current
    }

    // MARK: - Persistence

    private var persistTask: Task<Void, Never>?

    /// 寫檔放到背景，且 0.3 秒內的連續變動只寫一次（不卡主執行緒）。
    private func persist() {
        guard let fileURL else { return }
        let snapshot = draft
        persistTask?.cancel()
        persistTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                if let snapshot {
                    let data = try JSONEncoder().encode(snapshot)
                    try data.write(to: fileURL, options: .atomic)
                } else if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
            } catch {
                // 草稿存檔失敗不影響使用，只是下次打開可能不在
            }
        }
    }

    private static func load(from fileURL: URL?) -> MenuDraft? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(MenuDraft.self, from: data)
    }
}
