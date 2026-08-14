import CoreLocation
import Combine

/// Publishes the device's current ground speed in km/h, derived from CoreLocation.
final class LocationSpeedProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var speedKmh: Double = 0
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        // No minimum-distance gate — take every fix the hardware offers, as fast as it offers it.
        manager.distanceFilter = kCLDistanceFilterNone
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermissionAndStart() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        // CoreLocation reports speed in m/s, and returns a negative value when it is invalid.
        let metersPerSecond = max(latest.speed, 0)
        speedKmh = metersPerSecond * 3.6
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Stage 1: no dedicated error UI yet, just stop reporting a stale speed.
        speedKmh = 0
    }
}
