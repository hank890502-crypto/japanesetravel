import CoreLocation
import Foundation

/// 一次性取得目前位置（用來讓搜尋結果偏向附近）。沒有權限或失敗就回 nil，不打擾使用者。
protocol CurrentLocationProvider: Sendable {
    func currentLocation() async -> CLLocationCoordinate2D?
}

@MainActor
final class LiveCurrentLocationProvider: NSObject, CurrentLocationProvider, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentLocation() async -> CLLocationCoordinate2D? {
        if let cached = manager.location, cached.timestamp.timeIntervalSinceNow > -300 {
            return cached.coordinate
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            return nil   // 這次先不等，下次搜尋就會用到
        case .denied, .restricted:
            return nil
        default:
            break
        }
        return await withCheckedContinuation { cont in
            continuation?.resume(returning: nil)
            continuation = cont
            manager.requestLocation()
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                self?.finish(nil)
            }
        }
    }

    private func finish(_ coordinate: CLLocationCoordinate2D?) {
        continuation?.resume(returning: coordinate)
        continuation = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in self.finish(coordinate) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}

struct MockCurrentLocationProvider: CurrentLocationProvider {
    func currentLocation() async -> CLLocationCoordinate2D? { nil }
}
