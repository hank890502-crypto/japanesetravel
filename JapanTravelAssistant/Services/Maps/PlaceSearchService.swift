import CoreLocation
import Foundation
import MapKit

/// 搜尋到的一個地點（還沒儲存）。
struct PlaceSearchResult: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var address: String?
    var latitude: Double
    var longitude: Double
    var phone: String?
    var suggestedCategory: PlaceCategory

    func toPlace() -> Place {
        Place(name: name, address: address, latitude: latitude, longitude: longitude, category: suggestedCategory, phone: phone)
    }
}

/// 找地點。第一版用 Apple 地圖的資料（MKLocalSearch），免費、不需要金鑰。
protocol PlaceSearchService: Sendable {
    /// near：使用者目前位置（有的話結果會偏向附近）；沒有就以日本全境搜尋。
    func search(_ query: String, near: CLLocationCoordinate2D?) async throws -> [PlaceSearchResult]
}

struct LocalPlaceSearchService: PlaceSearchService {
    /// 日本全境（沒有定位時的預設範圍）
    static let japanRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 36.2, longitude: 138.2),
        span: MKCoordinateSpan(latitudeDelta: 18, longitudeDelta: 18)
    )

    func search(_ query: String, near: CLLocationCoordinate2D?) async throws -> [PlaceSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.pointOfInterest, .address]
        if let near {
            request.region = MKCoordinateRegion(center: near, span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3))
        } else {
            request.region = Self.japanRegion
        }
        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.prefix(15).map(Self.result(from:))
        } catch {
            if let mkError = error as? MKError, mkError.code == .placemarkNotFound {
                return []
            }
            throw UserFacingError(title: "找不到地點", message: "請確認網路連線，或換個關鍵字（例如加上城市名稱）。")
        }
    }

    static func result(from item: MKMapItem) -> PlaceSearchResult {
        let placemark = item.placemark
        let coordinate = placemark.coordinate
        return PlaceSearchResult(
            id: "\(coordinate.latitude),\(coordinate.longitude),\(item.name ?? "")",
            name: item.name ?? placemark.title ?? "地點",
            address: Self.address(from: placemark),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            phone: item.phoneNumber,
            suggestedCategory: Self.category(for: item)
        )
    }

    /// 日本地址的順序：郵遞區號、都道府縣、市區町村、町名番地。
    static func address(from placemark: MKPlacemark) -> String? {
        var parts: [String] = []
        if let postal = placemark.postalCode { parts.append("〒\(postal)") }
        let body = [placemark.administrativeArea, placemark.locality, placemark.subLocality, placemark.thoroughfare, placemark.subThoroughfare]
            .compactMap { $0?.nilIfBlank }
        if !body.isEmpty {
            parts.append(body.joined())
        } else if let title = placemark.title?.nilIfBlank {
            parts.append(title)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    static func category(for item: MKMapItem) -> PlaceCategory {
        guard let poi = item.pointOfInterestCategory else { return .other }
        switch poi {
        case .hotel: return .hotel
        case .publicTransport, .airport: return .station
        case .restaurant, .cafe, .bakery, .brewery, .foodMarket, .nightlife: return .restaurant
        case .store, .pharmacy: return .shopping
        case .museum, .park, .amusementPark, .aquarium, .zoo, .theater, .nationalPark, .beach: return .sight
        default: return .other
        }
    }
}

/// Preview / 測試用。
struct MockPlaceSearchService: PlaceSearchService {
    func search(_ query: String, near: CLLocationCoordinate2D?) async throws -> [PlaceSearchResult] {
        try await Task.sleep(for: .milliseconds(200))
        return [
            PlaceSearchResult(id: "1", name: "東京駅", address: "〒100-0005 東京都千代田区丸の内1丁目", latitude: 35.681236, longitude: 139.767125, phone: nil, suggestedCategory: .station),
            PlaceSearchResult(id: "2", name: "東京ステーションホテル", address: "〒100-0005 東京都千代田区丸の内1丁目9-1", latitude: 35.6812, longitude: 139.7671, phone: "+81-3-5220-1111", suggestedCategory: .hotel),
        ].filter { query.isEmpty || $0.name.contains(query) || query.contains("東京") }
    }
}
