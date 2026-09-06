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

    func clear() {
        draft = nil
        sourceImages = []
    }

    /// 把「其他文字」裡的一行移進菜單（回傳移進去的那一筆，讓畫面可以直接開編輯）。
    @discardableResult
    func promoteOtherLine(id: UUID) -> MenuItemDraft? {
        guard var current = draft, let index = current.otherLines.firstIndex(where: { $0.id == id }) else { return nil }
        let line = current.otherLines.remove(at: index)
        current.items.append(line)
        draft = current
        return line
    }

    struct ImportSummary: Hashable {
        var updated: Int
        var added: Int
        var total: Int { updated + added }
    }

    /// 用 ChatGPT 匯入的項目「取代」目前的菜單（從零建立一份新的）。
    @discardableResult
    func replace(with imported: [MenuImportParser.ImportedItem]) -> ImportSummary {
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
        draft = MenuDraft(items: items, sectionChineseNames: chinese)
        sourceImages = []
        return ImportSummary(updated: 0, added: items.count)
    }

    /// 把 ChatGPT 匯入的項目合併進目前的菜單：
    /// 日文名稱對得上的 → 更新中文、價格、說明、分類；對不上的 → 新增。沒有草稿就直接建立。
    @discardableResult
    func merge(imported: [MenuImportParser.ImportedItem]) -> ImportSummary {
        var current = draft ?? MenuDraft()
        var updated = 0
        var added = 0

        for item in imported {
            let key = PriceParser.normalize(item.japaneseName).replacingOccurrences(of: " ", with: "")
            guard !key.isEmpty else { continue }
            if let index = current.items.firstIndex(where: { existing in
                let existingKey = existing.normalizedJapaneseName
                return existingKey == key || (existingKey.count >= 3 && key.contains(existingKey)) || (key.count >= 3 && existingKey.contains(key))
            }) {
                var existing = current.items[index]
                existing.japaneseName = item.japaneseName
                if let chinese = item.chineseName.nilIfBlank { existing.chineseName = chinese }
                if let price = item.price { existing.priceText = "\(price)" }
                if let note = item.note { existing.note = note }
                if let section = item.section { existing.sectionName = section }
                if !item.options.isEmpty { existing.options = Self.optionDrafts(from: item.options) }
                if let reading = item.reading { existing.reading = reading }
                current.items[index] = existing
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
            if let section = item.section?.nilIfBlank, let zh = item.sectionChinese?.nilIfBlank {
                current.sectionChineseNames[section] = zh
            }
            // 其他文字裡若有同名的，移除（已經變成菜了）
            current.otherLines.removeAll { $0.normalizedJapaneseName == key }
        }
        draft = current
        return ImportSummary(updated: updated, added: added)
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
