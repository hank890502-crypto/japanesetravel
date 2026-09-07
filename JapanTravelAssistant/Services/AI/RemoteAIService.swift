import Foundation
import UIKit

/// 呼叫「自己的伺服器」。手機端沒有任何 AI 金鑰；伺服器再去呼叫 OpenAI / Gemini / Claude。
/// HTTP 介面規格見 docs/AI_BACKEND.md，Supabase Edge Function 範本見 supabase/functions/ai/。
struct RemoteAIService: AIService {
    let baseURL: URL
    /// 伺服器密碼（選填）：與伺服器環境變數 APP_TOKEN 相同的字串，放在 X-App-Token header，讓伺服器只接受這個 App 的呼叫。
    var appToken: String? = nil
    var session: URLSession = .shared
    var timeout: TimeInterval = 60

    static let tokenHeader = "X-App-Token"

    var isEnabled: Bool { true }
    var providerName: String { AIProviderKind.remoteBackend.displayName }

    // MARK: - 介面資料格式（與伺服器約定的 JSON）

    struct MenuRequest: Encodable { var lines: [String]; var imageBase64: String? }
    struct MenuResponse: Decodable {
        struct Option: Decodable { var group: String; var japanese: String; var chinese: String?; var priceDelta: Decimal? }
        struct Item: Decodable {
            var japanese: String; var chinese: String?; var reading: String?; var price: Decimal?
            var section: String?; var sectionChinese: String?; var note: String?; var options: [Option]?
        }
        var restaurantName: String?
        var items: [Item]
    }
    struct TranslateRequest: Encodable { var text: String; var target: String }
    struct TranslateResponse: Decodable { var translated: String; var reading: String? }
    struct ImageRequest: Encodable { var imageBase64: String }
    struct ProductResponse: Decodable { var productName: String?; var chineseName: String?; var price: Decimal?; var notes: String? }
    struct ReceiptResponse: Decodable {
        struct Line: Decodable { var name: String; var price: Decimal?; var quantity: Int? }
        var storeName: String?; var total: Decimal?; var lines: [Line]
    }

    // MARK: - AIService

    func analyzeMenu(textBlocks: [RecognizedTextBlock], image: UIImage?) async throws -> MenuAnalysis {
        let response: MenuResponse = try await post("menu/analyze", body: MenuRequest(lines: textBlocks.map(\.text), imageBase64: image.flatMap(Self.encode)))
        return MenuAnalysis(restaurantName: response.restaurantName, items: response.items.map { item in
            MenuAnalysis.ItemDraft(
                japaneseName: item.japanese, chineseName: item.chinese, reading: item.reading, price: item.price,
                sectionName: item.section, sectionChinese: item.sectionChinese, note: item.note,
                options: (item.options ?? []).map { .init(groupName: $0.group, japaneseName: $0.japanese, chineseName: $0.chinese, priceDelta: $0.priceDelta ?? 0) },
                confidence: nil
            )
        })
    }

    func analyzeProduct(image: UIImage) async throws -> ProductAnalysis {
        guard let encoded = Self.encode(image) else { throw UserFacingError(title: "無法讀取照片", message: "請換一張照片。") }
        let r: ProductResponse = try await post("product/analyze", body: ImageRequest(imageBase64: encoded))
        return ProductAnalysis(productName: r.productName, chineseName: r.chineseName, price: r.price, notes: r.notes)
    }

    func analyzeReceipt(image: UIImage) async throws -> ReceiptAnalysis {
        guard let encoded = Self.encode(image) else { throw UserFacingError(title: "無法讀取照片", message: "請換一張照片。") }
        let r: ReceiptResponse = try await post("receipt/analyze", body: ImageRequest(imageBase64: encoded))
        return ReceiptAnalysis(storeName: r.storeName, total: r.total, lines: r.lines.map { .init(name: $0.name, price: $0.price, quantity: $0.quantity) })
    }

    func translate(_ text: String, to language: TranslationLanguage) async throws -> Translation {
        let r: TranslateResponse = try await post("translate", body: TranslateRequest(text: text, target: language.rawValue))
        return Translation(original: text, translated: r.translated, reading: r.reading)
    }

    // MARK: - Private

    private func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let appToken = appToken?.nilIfBlank {
            request.setValue(appToken, forHTTPHeaderField: Self.tokenHeader)
        }
        request.httpBody = try JSONEncoder().encode(body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UserFacingError.from(error) == .unknown
                ? UserFacingError(title: "AI 服務沒有回應", message: "請確認手機有連上網路。一直不行的話，請家人檢查「設定」裡的 AI 服務。")
                : UserFacingError.from(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw UserFacingError(title: "AI 服務出了點問題", message: "請稍後再試。如果一直失敗，請家人檢查「設定」裡的 AI 服務。")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw UserFacingError(title: "AI 服務不接受這個密碼", message: "請家人到「設定 → AI 幫手」檢查伺服器密碼有沒有填對。", isRetryable: false)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UserFacingError(title: "AI 服務出了點問題", message: "請稍後再試。如果一直失敗，請家人檢查「設定」裡的 AI 服務。")
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw UserFacingError(title: "AI 回覆的格式不對", message: "AI 回傳的內容 App 看不懂。你可以自己輸入，或請家人檢查 AI 服務。", isRetryable: false)
        }
    }

    /// 照片縮到 1280px、JPEG 70%，再轉 base64（省流量、省 token）。
    static func encode(_ image: UIImage) -> String? {
        image.downscaled(maxDimension: 1280).jpegData(compressionQuality: 0.7)?.base64EncodedString()
    }
}
