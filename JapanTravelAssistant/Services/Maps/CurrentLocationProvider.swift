import CoreLocation
import Foundation

/// 一次性取得目前位置（用來讓搜尋結果偏向附近、地圖顯示「我在哪裡」）。
/// 沒有權限或失敗就回 nil，不打擾使用者。
protocol CurrentLocationProvider: Sendable {
    func currentLocation() async -> CLLocationCoordinate2D?
}

/// 注意：完全不同步讀取 CLLocationManager 的 location / authorizationStatus，
/// 那些取值在主執行緒上會等 XPC 回應，模擬器上會整個卡住。狀態一律由 delegate 回呼更新。
@MainActor
final class LiveCurrentLocationProvider: NSObject, CurrentLocationProvider, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var status: CLAuthorizationStatus?
    private var lastLocation: (coordinate: CLLocationCoordinate2D, at: Date)?
    private var continuations: [CheckedContinuation<CLLocationCoordinate2D?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self   // 設定 delegate 後系統會回呼一次 didChangeAuthorization
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentLocation() async -> CLLocationCoordinate2D? {
        if let cached = lastLocation, cached.at.timeIntervalSinceNow > -300 {
            return cached.coordinate
        }
        switch status {
        case nil, .notDetermined?:
            manager.requestWhenInUseAuthorization()   // 這次先不等，下次就會用到
            return nil
        case .denied?, .restricted?:
            return nil
        default:
            break
        }
        return await withCheckedContinuation { cont in
            continuations.append(cont)
            if continuations.count == 1 {
                manager.requestLocation()
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(5))
                    self?.finish(nil)
                }
            }
        }
    }

    private func finish(_ coordinate: CLLocationCoordinate2D?) {
        let pending = continuations
        continuations = []
        pending.forEach { $0.resume(returning: coordinate) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus   // delegate 回呼裡讀取是安全的
        Task { @MainActor in self.status = newStatus }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in
            if let coordinate { self.lastLocation = (coordinate, .now) }
            self.finish(coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}

struct MockCurrentLocationProvider: CurrentLocationProvider {
    func currentLocation() async -> CLLocationCoordinate2D? { nil }
}
