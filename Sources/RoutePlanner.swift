import MapKit
import Foundation

/// Requests driving directions from the current location to a chosen destination and
/// holds the resulting route (polyline + ETA) for the map and the interval display.
final class RoutePlanner: ObservableObject {
    @Published private(set) var route: MKRoute?
    @Published private(set) var destination: MKMapItem?
    @Published private(set) var isPlanning = false
    @Published var errorMessage: String?

    private let locationProvider: LocationSpeedProvider

    init(locationProvider: LocationSpeedProvider) {
        self.locationProvider = locationProvider
    }

    func planRoute(to destination: MKMapItem) {
        guard let current = locationProvider.lastLocation else {
            errorMessage = "Waiting for a GPS fix before routing."
            return
        }

        self.destination = destination
        self.route = nil
        isPlanning = true
        errorMessage = nil

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: current.coordinate))
        request.destination = destination
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        MKDirections(request: request).calculate { [weak self] response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isPlanning = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.route = response?.routes.first
            }
        }
    }

    func clear() {
        route = nil
        destination = nil
        errorMessage = nil
    }
}
