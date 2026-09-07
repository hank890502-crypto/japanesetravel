import CoreLocation
import Foundation
import MapKit

/// 把「日文地址」或「日文名稱」變成座標（Google／Yahoo 導航需要座標）。免費、不需金鑰。
protocol PlaceGeocoder: Sendable {
    func coordinate(address: String?, name: String?) async -> (latitude: Double, longitude: Double, address: String?)?
}

struct LiveGeocoder: PlaceGeocoder {
    func coordinate(address: String?, name: String?) async -> (latitude: Double, longitude: Double, address: String?)? {
        // 1. 地址 → 座標
        if let address = address?.nilIfBlank {
            if let placemark = try? await CLGeocoder().geocodeAddressString(address, in: nil, preferredLocale: Locale(identifier: "ja_JP")).first,
               let location = placemark.location {
                return (location.coordinate.latitude, location.coordinate.longitude, nil)
            }
        }
        // 2. 名稱（加地址）→ 搜地圖
        let query = [name?.nilIfBlank, address?.nilIfBlank].compactMap { $0 }.joined(separator: " ")
        guard !query.isEmpty else { return nil }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = LocalPlaceSearchService.japanRegion
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let coordinate = item.placemark.coordinate
        return (coordinate.latitude, coordinate.longitude, LocalPlaceSearchService.address(from: item.placemark))
    }
}

struct MockGeocoder: PlaceGeocoder {
    func coordinate(address: String?, name: String?) async -> (latitude: Double, longitude: Double, address: String?)? {
        (35.1681, 136.9086, nil)
    }
}
