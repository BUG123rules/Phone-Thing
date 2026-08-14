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

    /// The compass direction you'd need to face to keep following the route from
    /// `location` — i.e. the bearing toward a point `lookahead` meters further along
    /// the route polyline from wherever on it you're currently closest to. Used as a
    /// fallback for map rotation when GPS course isn't available (e.g. stopped).
    func headingToFollowRoute(from location: CLLocation, lookahead: CLLocationDistance = 30) -> CLLocationDirection? {
        guard let route else { return nil }
        let points = route.polyline.points()
        let count = route.polyline.pointCount
        guard count >= 2 else { return nil }

        let currentPoint = MKMapPoint(location.coordinate)

        var bestDistance = Double.greatestFiniteMagnitude
        var bestSegmentIndex = 0
        var bestProjected = points[0]

        for i in 0..<(count - 1) {
            let projected = Self.closestPoint(to: currentPoint, segmentStart: points[i], segmentEnd: points[i + 1])
            let distance = currentPoint.distance(to: projected)
            if distance < bestDistance {
                bestDistance = distance
                bestSegmentIndex = i
                bestProjected = projected
            }
        }

        var remaining = lookahead
        var segmentStart = bestProjected
        var index = bestSegmentIndex

        while index < count - 1 {
            let segmentEnd = points[index + 1]
            let segmentLength = segmentStart.distance(to: segmentEnd)
            if segmentLength >= remaining {
                let t = segmentLength > 0 ? remaining / segmentLength : 0
                let target = MKMapPoint(
                    x: segmentStart.x + (segmentEnd.x - segmentStart.x) * t,
                    y: segmentStart.y + (segmentEnd.y - segmentStart.y) * t
                )
                return Self.bearing(from: location.coordinate, to: target.coordinate)
            }
            remaining -= segmentLength
            segmentStart = segmentEnd
            index += 1
        }

        // Ran off the end of the route (near the destination) — aim at the endpoint.
        return Self.bearing(from: location.coordinate, to: points[count - 1].coordinate)
    }

    private static func closestPoint(to point: MKMapPoint, segmentStart a: MKMapPoint, segmentEnd b: MKMapPoint) -> MKMapPoint {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let lengthSquared = abx * abx + aby * aby
        guard lengthSquared > 0 else { return a }
        let t = min(max(((point.x - a.x) * abx + (point.y - a.y) * aby) / lengthSquared, 0), 1)
        return MKMapPoint(x: a.x + abx * t, y: a.y + aby * t)
    }

    private static func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let deltaLon = (end.longitude - start.longitude) * .pi / 180

        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let radians = atan2(y, x)
        return (radians * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}
