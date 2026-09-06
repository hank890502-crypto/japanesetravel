import Foundation
import UIKit

// MARK: - 輸出型別（先定義好，未來各家 Provider 都回傳同樣的結構）

/// AI 從 OCR 文字／圖片整理出的菜單草稿。
struct MenuAnalysis: Hashable, Sendable {
    struct ItemDraft: Hashable, Sendable {
        var japaneseName: String
        var chineseName: String?
        var reading: String?
        var price: Decimal?
        var sectionName: String?
        var confidence: Double?
    }
    var restaurantName: String?
    var items: [ItemDraft]
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

/// 目前可選的 AI 供應商。M5 加入設定 UI；正式版一律走自己的 Backend，不在 App 放 Key。
enum AIProviderKind: String, CaseIterable, Codable, Sendable {
    case disabled
    case mock
    // 未來：case remoteBackend（iPhone → 自己的 Backend → OpenAI / Gemini / Claude）

    var displayName: String {
        switch self {
        case .disabled: "未啟用"
        case .mock: "測試用（假資料）"
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
        let items = textBlocks.map { block -> MenuAnalysis.ItemDraft in
            let (name, price) = PriceParser.split(block.text)
            let known = Self.dictionary[name]
            return .init(japaneseName: name, chineseName: known?.chinese, reading: known?.reading, price: price, sectionName: nil, confidence: block.confidence)
        }
        return MenuAnalysis(restaurantName: nil, items: items)
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
