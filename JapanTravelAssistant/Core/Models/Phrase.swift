import Foundation

/// 溝通助手的情境分類。
enum PhraseCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case hotel
    case carRental
    case restaurant
    case onsen
    case shopping
    case transport
    case emergency

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hotel: "飯店"
        case .carRental: "租車"
        case .restaurant: "餐廳"
        case .onsen: "溫泉"
        case .shopping: "購物"
        case .transport: "交通"
        case .emergency: "緊急"
        }
    }

    var subtitle: String {
        switch self {
        case .hotel: "入住、客房服務、早餐、退房"
        case .carRental: "取車、加油、遇到問題、還車"
        case .restaurant: "訂位、點餐、用餐中、結帳"
        case .onsen: "入場、泡湯規矩、溫泉旅館"
        case .shopping: "找商品、免稅、藥妝、電器"
        case .transport: "買票、電車、計程車、巴士"
        case .emergency: "求助、不舒服、東西掉了、迷路"
        }
    }

    var systemImage: String {
        switch self {
        case .hotel: "bed.double.fill"
        case .carRental: "car.fill"
        case .restaurant: "fork.knife"
        case .onsen: "drop.fill"
        case .shopping: "bag.fill"
        case .transport: "tram.fill"
        case .emergency: "cross.case.fill"
        }
    }
}

/// 一句常用日文。純 App 端資料（來自 phrases.json），不進資料庫。
struct Phrase: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var category: PhraseCategory
    /// 場面（例如 入住、退房）。同一分類底下再分區塊。
    var scene: String?
    var chinese: String
    var japanese: String
    var reading: String?
}
