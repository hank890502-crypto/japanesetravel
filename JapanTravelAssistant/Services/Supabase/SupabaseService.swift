import Foundation
import Supabase

/// Supabase 連線與身分（匿名登入）。Repository 透過這個 protocol 拿 client 與使用者 id；View 永遠不碰它。
protocol SupabaseService: Sendable {
    var isConfigured: Bool { get }
    /// 確保有匿名使用者，回傳其 id。
    func signInAnonymouslyIfNeeded() async throws -> UUID
}

/// 尚未設定 Supabase 時使用。
struct UnconfiguredSupabaseService: SupabaseService {
    var isConfigured: Bool { false }
    func signInAnonymouslyIfNeeded() async throws -> UUID {
        throw UserFacingError.collaborationNotConfigured
    }
}

/// 真正的 Supabase 連線。整個 App 只建立一個 client（由 AppDependencies 持有，不是 singleton）。
final class LiveSupabaseService: SupabaseService {
    let client: SupabaseClient

    init(url: URL, anonKey: String) {
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(
                db: .init(encoder: SupabaseCoding.encoder, decoder: SupabaseCoding.decoder)
            )
        )
    }

    var isConfigured: Bool { true }

    func signInAnonymouslyIfNeeded() async throws -> UUID {
        if let session = try? await client.auth.session, !session.isExpired {
            return session.user.id
        }
        do {
            let session = try await client.auth.signInAnonymously()
            return session.user.id
        } catch {
            throw UserFacingError(
                title: "無法連上多人點餐",
                message: "請確認網路連線後再試一次。"
            )
        }
    }
}

/// 資料庫欄位是 snake_case、時間是 Postgres 格式；這裡統一轉換，Domain Model 不用寫 CodingKeys。
enum SupabaseCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = parsePostgresDate(raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "無法解析日期：\(raw)")
        }
        return decoder
    }()

    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// 2026-09-07T01:23:45.123456+00:00、2026-09-07T01:23:45+00:00、2026-09-07 01:23:45.12345+00
    static func parsePostgresDate(_ raw: String) -> Date? {
        var text = raw.replacingOccurrences(of: " ", with: "T")
        if text.hasSuffix("+00") { text += ":00" }
        if let range = text.range(of: #"\.\d+"#, options: .regularExpression) {
            let digits = text[range].dropFirst()
            let trimmed = "." + digits.prefix(3) + String(repeating: "0", count: max(0, 3 - digits.count))
            text.replaceSubrange(range, with: trimmed)
            return fractional.date(from: text) ?? plain.date(from: text.replacingOccurrences(of: trimmed, with: ""))
        }
        return plain.date(from: text)
    }
}
