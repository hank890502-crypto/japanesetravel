import Foundation
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence（Foundation Models framework，iOS 26+）：在手機上跑的語言模型。
/// 免費、離線、資料不離開手機。只處理文字，所以需要看圖的功能（商品、收據）不支援。
enum AppleIntelligence {
    struct Availability: Equatable {
        var isAvailable: Bool
        /// 不可用時給使用者看的白話原因
        var reason: String?
    }

    static var availability: Availability {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return Availability(isAvailable: true, reason: nil)
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return Availability(isAvailable: false, reason: "這台裝置不支援 Apple 智慧（需要 iPhone 15 Pro 以後、或 M 系列／A17 Pro 的 iPad）。")
                case .appleIntelligenceNotEnabled:
                    return Availability(isAvailable: false, reason: "請到 iPhone 的「設定 → Apple 智慧與 Siri」開啟 Apple 智慧。")
                case .modelNotReady:
                    return Availability(isAvailable: false, reason: "Apple 智慧的模型還在下載中，請稍後再試（接上 Wi-Fi 與電源會比較快）。")
                @unknown default:
                    return Availability(isAvailable: false, reason: "目前無法使用 Apple 智慧。")
                }
            }
        }
        #endif
        return Availability(isAvailable: false, reason: "需要 iOS 26 以上才能使用 Apple 智慧。")
    }

    /// 通用的角色設定：日本旅遊助手、對長輩說話。
    static let travelAssistantInstructions = """
    你是「日本旅遊助手」，服務對象是 65 到 75 歲、不懂日文、不熟手機的台灣長輩。
    專長：日本自由行、日本餐廳與菜單、日本商品（藥妝、超市、電器、伴手禮）、交通、飯店、溫泉、購物退稅、日本的禮節與習慣。
    回答規則：
    1. 一律用繁體中文（台灣用語），每句話不超過 25 個字，先講結論再講原因，最多 5 句。
    2. 不用專業術語、不用英文縮寫；一定要用日文時，日文後面加上中文意思。
    3. 你沒有連網，不知道今天的匯率、營業時間、價格、天氣、班次。被問到這類問題時，先給一般常識，再提醒「請以現場或官網為準」。
    4. 不確定就直接說不確定，不要編造店名、地址、電話。
    5. 牽涉安全與健康（過敏、用藥、生病）時，建議找店員、藥師或醫師確認。
    6. 語氣親切、有耐心，像對自己的長輩說話。
    """
}

#if canImport(FoundationModels)
@available(iOS 26, *)
struct AppleIntelligenceAIService: AIService {
    var isEnabled: Bool { AppleIntelligence.availability.isAvailable }
    var providerName: String { AIProviderKind.appleIntelligence.displayName }

    // MARK: - 結構化輸出（模型直接吐出 App 要的欄位，不用再解析文字）

    @Generable
    struct MenuResult {
        @Guide(description: "餐廳名稱，看不出來就留空字串")
        var restaurantName: String
        @Guide(description: "菜單上的每一道菜")
        var items: [MenuItemResult]
    }

    @Generable
    struct MenuItemResult {
        @Guide(description: "菜名的日文原文，照菜單上的字，不要改")
        var japanese: String
        @Guide(description: "台灣人一看就懂的繁體中文菜名")
        var chinese: String
        @Guide(description: "平文式羅馬拼音，例如 karaage")
        var reading: String
        @Guide(description: "價格數字（日圓），沒有就 0")
        var price: Int
        @Guide(description: "分類的日文，例如 揚げ物、ドリンク；沒有就留空字串")
        var section: String
        @Guide(description: "分類的繁體中文，例如 炸物、飲料；沒有就留空字串")
        var sectionChinese: String
        @Guide(description: "可選的份量、套餐升級、配料")
        var options: [MenuOptionResult]
    }

    @Generable
    struct MenuOptionResult {
        @Guide(description: "選項群組的中文，例如 份量、套餐")
        var group: String
        @Guide(description: "選項的日文，例如 大盛り")
        var japanese: String
        @Guide(description: "選項的繁體中文，例如 大份")
        var chinese: String
        @Guide(description: "相對基本價的加減金額，例如 150、-100、0")
        var priceDelta: Int
    }

    @Generable
    struct TranslationResult {
        @Guide(description: "繁體中文翻譯（台灣用語）")
        var translated: String
        @Guide(description: "平文式羅馬拼音")
        var reading: String
    }

    private static let menuInstructions = """
    你是日本餐廳菜單的整理助手，服務對象是不懂日文的台灣家庭。
    輸入是從菜單照片辨識出來的文字（可能有雜訊、順序可能亂掉）。
    請整理出每一道菜：日文原文照抄不要改字；繁體中文要讓台灣人一看就懂；價格只取數字（含稅價優先）；
    盡量分類（菜單有分類就照菜單，沒有就依類型分）；「大盛り +150」「定食セット +300」這類是選項，priceDelta 是相對基本價的加減。
    不是菜的文字（店名、說明、注意事項）不要列入。
    """

    // MARK: - AIService

    func analyzeMenu(textBlocks: [RecognizedTextBlock], image: UIImage?) async throws -> MenuAnalysis {
        try await ensureAvailable()
        let lines = textBlocks.map(\.text).filter { !$0.isEmpty }
        guard !lines.isEmpty else { return MenuAnalysis(restaurantName: nil, items: []) }
        // 模型的輸入有限，太長的菜單分批
        var items: [MenuAnalysis.ItemDraft] = []
        var restaurantName: String?
        for chunk in lines.chunked(into: 40) {
            let session = LanguageModelSession(instructions: Self.menuInstructions)
            let prompt = "菜單文字：\n" + chunk.joined(separator: "\n")
            let result: MenuResult
            do {
                result = try await session.respond(to: prompt, generating: MenuResult.self).content
            } catch {
                throw Self.map(error)
            }
            if restaurantName == nil, !result.restaurantName.isEmpty { restaurantName = result.restaurantName }
            items += result.items.compactMap { item in
                guard !item.japanese.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                return MenuAnalysis.ItemDraft(
                    japaneseName: item.japanese,
                    chineseName: item.chinese.nilIfBlank,
                    reading: item.reading.nilIfBlank,
                    price: item.price > 0 ? Decimal(item.price) : nil,
                    sectionName: item.section.nilIfBlank,
                    sectionChinese: item.sectionChinese.nilIfBlank,
                    note: nil,
                    options: item.options.compactMap { option in
                        guard !option.japanese.isEmpty else { return nil }
                        return .init(groupName: option.group.nilIfBlank ?? "選項", japaneseName: option.japanese, chineseName: option.chinese.nilIfBlank, priceDelta: Decimal(option.priceDelta))
                    },
                    confidence: nil
                )
            }
        }
        return MenuAnalysis(restaurantName: restaurantName, items: items)
    }

    func translate(_ text: String, to language: TranslationLanguage) async throws -> Translation {
        try await ensureAvailable()
        let session = LanguageModelSession(instructions: "把日文翻成繁體中文（台灣用語），並給平文式羅馬拼音。這通常是菜名、商品名或店員說的一句話。")
        do {
            let result = try await session.respond(to: text, generating: TranslationResult.self).content
            return Translation(original: text, translated: result.translated, reading: result.reading.nilIfBlank)
        } catch {
            throw Self.map(error)
        }
    }

    func analyzeProduct(image: UIImage) async throws -> ProductAnalysis {
        throw UserFacingError(title: "這個功能需要看照片", message: "Apple 智慧目前只能處理文字。要辨識商品照片，請在設定選「自己的伺服器」。", isRetryable: false)
    }

    func analyzeReceipt(image: UIImage) async throws -> ReceiptAnalysis {
        throw UserFacingError(title: "這個功能需要看照片", message: "Apple 智慧目前只能處理文字。要核對收據，請在設定選「自己的伺服器」。", isRetryable: false)
    }

    // MARK: - Private

    private func ensureAvailable() async throws {
        let availability = AppleIntelligence.availability
        guard availability.isAvailable else {
            throw UserFacingError(title: "Apple 智慧目前無法使用", message: availability.reason ?? "", isRetryable: false)
        }
    }

    /// 把模型的錯誤翻成白話
    static func map(_ error: Error) -> UserFacingError {
        if let userFacing = error as? UserFacingError { return userFacing }
        if let generation = error as? LanguageModelSession.GenerationError {
            switch generation {
            case .exceededContextWindowSize:
                return UserFacingError(title: "內容太長", message: "請分成幾次，或減少一次處理的文字。")
            case .guardrailViolation:
                return UserFacingError(title: "這個內容 Apple 智慧不方便回答", message: "請換個方式問，或自己輸入。", isRetryable: false)
            case .unsupportedLanguageOrLocale:
                return UserFacingError(title: "Apple 智慧不支援這個語言", message: "請確認 iPhone 的語言設定是繁體中文。", isRetryable: false)
            default:
                break
            }
        }
        return UserFacingError(title: "Apple 智慧沒有回應", message: "請再試一次。")
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
#endif
