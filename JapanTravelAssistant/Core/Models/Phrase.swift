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
        case .hotel: "入住、行李、早餐"
        case .carRental: "取車、還車、加油"
        case .restaurant: "訂位、點餐、結帳"
        case .onsen: "入浴、毛巾、規定"
        case .shopping: "找商品、尺寸、免稅"
        case .transport: "買票、月台、轉乘"
        case .emergency: "求助、醫院、警察"
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
    var chinese: String
    var japanese: String
    var reading: String?
}
