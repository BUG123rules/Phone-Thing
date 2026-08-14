import MapKit
import Foundation

/// Requests driving directions to a chosen destination and holds the resulting route
/// (polyline + ETA) for the map and the interval display.
///
/// The route's starting point defaults to the current GPS location, but can be
/// overridden with `setStartingPoint` for planning a route that doesn't begin where
/// you're currently standing.
final class RoutePlanner: ObservableObject {
    @Published private(set) var route: MKRoute?
    @Published private(set) var destination: MKMapItem?
    @Published private(set) var startingPoint: MKMapItem?
    @Published private(set) var isPlanning = false
    @Published var errorMessage: String?

    private let locationProvider: LocationSpeedProvider

    init(locationProvider: LocationSpeedProvider) {
        self.locationProvider = locationProvider
    }

    /// nil resets to the current GPS location.
    func setStartingPoint(_ item: MKMapItem?) {
        startingPoint = item
        replanIfPossible()
    }

    func planRoute(to destination: MKMapItem) {
        self.destination = destination
        replanIfPossible()
    }

    func replanIfPossible() {
        guard let destination else { return }
        guard let source = resolvedSource() else {
            errorMessage = "Waiting for a GPS fix before routing."
            return
        }

        self.route = nil
        isPlanning = true
        errorMessage = nil

        let request = MKDirections.Request()
        request.source = source
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

    private func resolvedSource() -> MKMapItem? {
        if let startingPoint {
            return startingPoint
        }
        guard let current = locationProvider.lastLocation else { return nil }
        return MKMapItem(placemark: MKPlacemark(coordinate: current.coordinate))
    }
}
