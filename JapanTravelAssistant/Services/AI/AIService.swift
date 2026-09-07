import Foundation
import UIKit

// MARK: - 輸出型別（先定義好，未來各家 Provider 都回傳同樣的結構）

/// AI 從 OCR 文字／圖片整理出的菜單草稿。
struct MenuAnalysis: Hashable, Sendable {
    struct OptionDraft: Hashable, Sendable {
        var groupName: String
        var japaneseName: String
        var chineseName: String?
        var priceDelta: Decimal
    }
    struct ItemDraft: Hashable, Sendable {
        var japaneseName: String
        var chineseName: String?
        var reading: String?
        var price: Decimal?
        var sectionName: String?
        var sectionChinese: String? = nil
        var note: String? = nil
        var options: [OptionDraft] = []
        var confidence: Double?
    }
    var restaurantName: String?
    var items: [ItemDraft]

    /// 轉成匯入格式，直接沿用 ChatGPT 匯入的合併邏輯。
    var importedItems: [MenuImportParser.ImportedItem] {
        items.map { item in
            MenuImportParser.ImportedItem(
                japaneseName: item.japaneseName,
                chineseName: item.chineseName ?? "",
                price: item.price,
                note: item.note,
                section: item.sectionName,
                sectionChinese: item.sectionChinese,
                options: item.options.map { .init(groupName: $0.groupName, japaneseName: $0.japaneseName, chineseName: $0.chineseName ?? "", priceDelta: $0.priceDelta) },
                reading: item.reading
            )
        }
    }
}

struct ProductAnalysis: Hashable, Sendable {
    var productName: String?
    var chineseName: String?
    var price: Decimal?
    var notes: String?
}

struct ReceiptAnalysis: Hashable, Sendable {
    struct Line: Hashable, Sendable {
        var name: String
        var price: Decimal?
        var quantity: Int?
    }
    var storeName: String?
    var total: Decimal?
    var lines: [Line]
}

struct Translation: Hashable, Sendable {
    var original: String
    var translated: String
    var reading: String?
}

enum TranslationLanguage: String, Sendable {
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
}

/// 目前可選的 AI 供應商。金鑰永遠不在 App 裡：正式使用走「自己的伺服器」（iPhone → 你的 Backend → OpenAI / Gemini / Claude）。
enum AIProviderKind: String, CaseIterable, Codable, Sendable {
    case disabled
    case appleIntelligence
    case mock
    case remoteBackend

    var displayName: String {
        switch self {
        case .disabled: "未啟用"
        case .appleIntelligence: "Apple 智慧（手機上處理）"
        case .mock: "測試用（假資料）"
        case .remoteBackend: "自己的伺服器"
        }
    }

    var explanation: String {
        switch self {
        case .disabled: "不使用 AI。菜單翻譯用內建詞彙表與 iPhone 離線翻譯。"
        case .appleIntelligence: "用 iPhone 內建的 Apple 智慧整理菜單、翻譯、回答問題。免費、離線、資料不離開手機。只能處理文字，不能看照片。"
        case .mock: "用假資料走完整流程，給開發測試用，不會連網。"
        case .remoteBackend: "把照片與文字送到你自己架的伺服器，由它去呼叫 AI。金鑰只放在伺服器上。"
        }
    }
}

// MARK: - Protocol

/// 所有 AI 功能的抽象介面。View 與 ViewModel 只認識這個 protocol。
protocol AIService: Sendable {
    var isEnabled: Bool { get }
    var providerName: String { get }

    func analyzeMenu(textBlocks: [RecognizedTextBlock], image: UIImage?) async throws -> MenuAnalysis
    func analyzeProduct(image: UIImage) async throws -> ProductAnalysis
    func analyzeReceipt(image: UIImage) async throws -> ReceiptAnalysis
    func translate(_ text: String, to language: TranslationLanguage) async throws -> Translation
}

// MARK: - Implementations

/// 預設：AI 未啟用。所有呼叫都丟出白話錯誤，不會 crash。
struct DisabledAIService: AIService {
    var isEnabled: Bool { false }
    var providerName: String { AIProviderKind.disabled.displayName }

    func analyzeMenu(textBlocks: [RecognizedTextBlock], image: UIImage?) async throws -> MenuAnalysis {
        throw UserFacingError.aiNotEnabled
    }
    func analyzeProduct(image: UIImage) async throws -> ProductAnalysis {
        throw UserFacingError.aiNotEnabled
    }
    func analyzeReceipt(image: UIImage) async throws -> ReceiptAnalysis {
        throw UserFacingError.aiNotEnabled
    }
    func translate(_ text: String, to language: TranslationLanguage) async throws -> Translation {
        throw UserFacingError.aiNotEnabled
    }
}

/// 測試用：回傳看起來合理的假資料，讓 UI 流程可以在沒有 API 的情況下完整走完。
struct MockAIService: AIService {
    var isEnabled: Bool { true }
    var providerName: String { AIProviderKind.mock.displayName }

    private static let dictionary: [String: (chinese: String, reading: String)] = [
        "若どり唐揚げ": ("炸嫩雞", "わかどり からあげ"),
        "手羽先": ("雞翅", "てばさき"),
        "味噌串カツ": ("味噌炸串", "みそ くしカツ"),
        "唐揚げ": ("炸雞", "からあげ"),
    ]

    func analyzeMenu(textBlocks: [RecognizedTextBlock], image: UIImage?) async throws -> MenuAnalysis {
        try await Task.sleep(for: .milliseconds(500))
        let items = textBlocks.compactMap { block -> MenuAnalysis.ItemDraft? in
            let (name, price) = PriceParser.split(block.text)
            guard !name.isEmpty else { return nil }
            let known = Self.dictionary[name]
            let section = Self.guessSection(name)
            return .init(
                japaneseName: name,
                chineseName: known?.chinese ?? MenuGlossary.bundled.translate(name),
                reading: known?.reading,
                price: price,
                sectionName: section?.ja,
                sectionChinese: section?.zh,
                note: nil,
                options: name.contains("カツ") || name.contains("定食") ? [.init(groupName: "份量", japaneseName: "大盛り", chineseName: "大份", priceDelta: 150)] : [],
                confidence: block.confidence
            )
        }
        return MenuAnalysis(restaurantName: "テスト食堂", items: items)
    }

    private static func guessSection(_ name: String) -> (ja: String, zh: String)? {
        if name.contains("揚") || name.contains("カツ") || name.contains("フライ") { return ("揚げ物", "炸物") }
        if name.contains("焼") || name.contains("串") { return ("焼き物", "烤物") }
        if name.contains("ビール") || name.contains("サワー") || name.contains("茶") || name.contains("酒") { return ("ドリンク", "飲料") }
        if name.contains("ご飯") || name.contains("ライス") || name.contains("丼") || name.contains("麺") { return ("ご飯・麺", "主食") }
        return nil
    }

    func analyzeProduct(image: UIImage) async throws -> ProductAnalysis {
        try await Task.sleep(for: .milliseconds(500))
        return ProductAnalysis(productName: "サンプル商品", chineseName: "範例商品", price: 980, notes: "測試資料")
    }

    func analyzeReceipt(image: UIImage) async throws -> ReceiptAnalysis {
        try await Task.sleep(for: .milliseconds(500))
        return ReceiptAnalysis(storeName: "サンプル店", total: 1510, lines: [
            .init(name: "若どり唐揚げ", price: 540, quantity: 1),
            .init(name: "手羽先", price: 430, quantity: 1),
            .init(name: "味噌串カツ", price: 540, quantity: 1),
        ])
    }

    func translate(_ text: String, to language: TranslationLanguage) async throws -> Translation {
        try await Task.sleep(for: .milliseconds(300))
        if let known = Self.dictionary[text] {
            return Translation(original: text, translated: known.chinese, reading: known.reading)
        }
        return Translation(original: text, translated: "（測試翻譯）\(text)", reading: nil)
    }
}
