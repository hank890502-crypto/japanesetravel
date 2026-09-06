import Foundation
import MapKit
import UIKit

/// 使用者可選的導航 App。
enum NavigationProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case appleMaps
    case googleMaps
    case yahooCarNavi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleMaps: "Apple 地圖"
        case .googleMaps: "Google 地圖"
        case .yahooCarNavi: "Yahoo! カーナビ"
        }
    }

    var systemImage: String {
        switch self {
        case .appleMaps: "map.fill"
        case .googleMaps: "globe.asia.australia.fill"
        case .yahooCarNavi: "car.fill"
        }
    }
}

/// 開啟外部地圖 App 導航。App 本身不做導航引擎。
protocol NavigationService: Sendable {
    /// 這台手機實際可用的導航 App（Apple 地圖永遠可用）。
    @MainActor func availableProviders() -> [NavigationProvider]
    @MainActor func open(_ place: Place, using provider: NavigationProvider) async throws
}

struct LiveNavigationService: NavigationService {
    @MainActor
    func availableProviders() -> [NavigationProvider] {
        NavigationProvider.allCases.filter { provider in
            switch provider {
            case .appleMaps: true
            case .googleMaps: UIApplication.shared.canOpenURL(URL(string: "comgooglemaps://")!)
            case .yahooCarNavi: UIApplication.shared.canOpenURL(URL(string: "yjcarnavi://")!)
            }
        }
    }

    @MainActor
    func open(_ place: Place, using provider: NavigationProvider) async throws {
        switch provider {
        case .appleMaps:
            try await openAppleMaps(place)
        case .googleMaps, .yahooCarNavi:
            guard let url = externalURL(for: place, provider: provider) else {
                throw UserFacingError(title: "無法開啟地圖", message: "這個地點沒有座標，請改用 Apple 地圖。", isRetryable: false)
            }
            let opened = await UIApplication.shared.open(url)
            if !opened {
                throw UserFacingError(title: "無法開啟 \(provider.displayName)", message: "手機裡可能沒有安裝這個 App，請改用 Apple 地圖。", isRetryable: false)
            }
        }
    }

    @MainActor
    private func openAppleMaps(_ place: Place) async throws {
        let mapItem: MKMapItem
        if let lat = place.latitude, let lon = place.longitude {
            let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
            mapItem = MKMapItem(placemark: placemark)
        } else if let address = place.address?.nilIfBlank {
            let placemarks = try await CLGeocoder().geocodeAddressString(address)
            guard let first = placemarks.first else {
                throw UserFacingError(title: "找不到這個地址", message: "請確認地址是否正確。", isRetryable: false)
            }
            mapItem = MKMapItem(placemark: MKPlacemark(placemark: first))
        } else {
            throw UserFacingError(title: "沒有地點資料", message: "這個地點沒有地址或座標。", isRetryable: false)
        }
        mapItem.name = place.name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }

    private func externalURL(for place: Place, provider: NavigationProvider) -> URL? {
        guard let lat = place.latitude, let lon = place.longitude else { return nil }
        switch provider {
        case .appleMaps:
            return nil
        case .googleMaps:
            return URL(string: "comgooglemaps://?daddr=\(lat),\(lon)&directionsmode=walking")
        case .yahooCarNavi:
            return URL(string: "yjcarnavi://navi/select?lat=\(lat)&lon=\(lon)&name=\(place.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        }
    }
}

/// Preview / 測試用：不真的開 App。
struct MockNavigationService: NavigationService {
    @MainActor func availableProviders() -> [NavigationProvider] { NavigationProvider.allCases }
    @MainActor func open(_ place: Place, using provider: NavigationProvider) async throws {}
}
