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
    /// 這台手機實際可用的導航 App（Apple 地圖永遠可用；Google 地圖沒裝會用網頁版）。
    @MainActor func availableProviders() -> [NavigationProvider]
    /// 有沒有安裝該 App（Apple 地圖永遠 true）
    @MainActor func isInstalled(_ provider: NavigationProvider) -> Bool
    @MainActor func open(_ place: Place, using provider: NavigationProvider) async throws
}

struct LiveNavigationService: NavigationService {
    @MainActor
    func isInstalled(_ provider: NavigationProvider) -> Bool {
        switch provider {
        case .appleMaps: true
        case .googleMaps: UIApplication.shared.canOpenURL(URL(string: "comgooglemaps://")!)
        case .yahooCarNavi: UIApplication.shared.canOpenURL(URL(string: "yjcarnavi://")!)
        }
    }

    @MainActor
    func availableProviders() -> [NavigationProvider] {
        // Apple 永遠可用；Google 沒裝也能開網頁版；Yahoo 一定要有 App
        NavigationProvider.allCases.filter { $0 != .yahooCarNavi || isInstalled(.yahooCarNavi) }
    }

    @MainActor
    func open(_ place: Place, using provider: NavigationProvider) async throws {
        switch provider {
        case .appleMaps:
            try await openAppleMaps(place)
        case .googleMaps:
            let url: URL?
            if isInstalled(.googleMaps) {
                url = externalURL(for: place, provider: .googleMaps)
            } else {
                url = googleWebURL(for: place)
            }
            guard let url else {
                throw UserFacingError(title: "無法開啟 Google 地圖", message: "這個地點沒有座標也沒有地址，請先修改地點。", isRetryable: false)
            }
            if !(await UIApplication.shared.open(url)) {
                throw UserFacingError(title: "無法開啟 Google 地圖", message: "請改用 Apple 地圖。", isRetryable: false)
            }
        case .yahooCarNavi:
            guard isInstalled(.yahooCarNavi) else {
                throw UserFacingError(title: "沒有安裝 Yahoo! カーナビ", message: "請先到 App Store 安裝（免費），或改用其他地圖。", isRetryable: false)
            }
            guard let url = externalURL(for: place, provider: .yahooCarNavi) else {
                throw UserFacingError(title: "這個地點還沒有座標", message: "Yahoo! カーナビ 需要座標。請稍等 App 補上座標，或改用 Apple 地圖。", isRetryable: false)
            }
            if !(await UIApplication.shared.open(url)) {
                throw UserFacingError(title: "無法開啟 Yahoo! カーナビ", message: "請改用其他地圖。", isRetryable: false)
            }
        }
    }

    /// Google 地圖網頁版：有座標用座標，沒有就用地址或名稱查
    private func googleWebURL(for place: Place) -> URL? {
        var components = URLComponents(string: "https://www.google.com/maps/dir/")!
        let destination: String
        if let lat = place.latitude, let lon = place.longitude {
            destination = "\(lat),\(lon)"
        } else if let address = place.address?.nilIfBlank {
            destination = "\(place.staffName) \(address)"
        } else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "destination", value: destination), URLQueryItem(name: "travelmode", value: "transit")]
        return components.url
    }

    @MainActor
    private func openAppleMaps(_ place: Place) async throws {
        let mapItem: MKMapItem
        if let lat = place.latitude, let lon = place.longitude {
            let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
            mapItem = MKMapItem(placemark: placemark)
            mapItem.name = place.staffName
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
            return URL(string: "yjcarnavi://navi/select?lat=\(lat)&lon=\(lon)&name=\(place.staffName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        }
    }
}

/// Preview / 測試用：不真的開 App。
struct MockNavigationService: NavigationService {
    @MainActor func availableProviders() -> [NavigationProvider] { NavigationProvider.allCases }
    @MainActor func isInstalled(_ provider: NavigationProvider) -> Bool { true }
    @MainActor func open(_ place: Place, using provider: NavigationProvider) async throws {}
}
