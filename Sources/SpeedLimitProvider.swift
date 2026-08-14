import CoreLocation
import Combine
import Foundation

/// Speed limit (km/h) for the road nearest the most recent location, sourced from
/// OpenStreetMap via the public Overpass API.
///
/// This is a free, keyless, shared community server — not something to hammer once
/// per GPS fix (~1 Hz). Queries are throttled by distance moved and time elapsed.
/// Coverage/accuracy depends on how well-tagged local roads are in OSM: a query that
/// finds no `maxspeed` tag nearby just leaves the last known value in place rather
/// than flickering to "unknown", since untagged short stretches of road are common.
final class SpeedLimitProvider: ObservableObject {
    @Published private(set) var speedLimitKmh: Double?

    private var cancellable: AnyCancellable?
    private var lastQueriedLocation: CLLocation?
    private var lastQueryDate: Date?
    private var isQuerying = false

    private let minDistanceBetweenQueries: CLLocationDistance = 40
    private let minTimeBetweenQueries: TimeInterval = 8

    private let session: URLSession = .shared
    private let overpassURL = URL(string: "https://overpass-api.de/api/interpreter")!

    init(locationProvider: LocationSpeedProvider) {
        cancellable = locationProvider.$lastLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                self?.considerQuerying(for: location)
            }
    }

    private func considerQuerying(for location: CLLocation) {
        guard !isQuerying else { return }

        if let lastLocation = lastQueriedLocation, let lastDate = lastQueryDate {
            let movedFarEnough = location.distance(from: lastLocation) >= minDistanceBetweenQueries
            let waitedLongEnough = Date().timeIntervalSince(lastDate) >= minTimeBetweenQueries
            guard movedFarEnough || waitedLongEnough else { return }
        }

        lastQueriedLocation = location
        lastQueryDate = Date()
        query(near: location)
    }

    private func query(near location: CLLocation) {
        isQuerying = true

        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        // Nearest tagged road within 25m; ask for a few candidates in case the closest
        // way back doesn't carry a maxspeed tag.
        let overpassQL = """
        [out:json][timeout:5];
        way(around:25,\(lat),\(lon))[highway][maxspeed];
        out tags 5;
        """

        var request = URLRequest(url: overpassURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "data", value: overpassQL)]
        request.httpBody = components.percentEncodedQuery.map { Data($0.utf8) }

        session.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            let parsed = data.flatMap(Self.parseNearestMaxSpeed(from:))
            DispatchQueue.main.async {
                self.isQuerying = false
                if let parsed {
                    self.speedLimitKmh = parsed
                }
            }
        }.resume()
    }

    private static func parseNearestMaxSpeed(from data: Data) -> Double? {
        struct OverpassResponse: Decodable {
            struct Element: Decodable {
                struct Tags: Decodable {
                    let maxspeed: String?
                }
                let tags: Tags?
            }
            let elements: [Element]
        }

        guard let response = try? JSONDecoder().decode(OverpassResponse.self, from: data) else { return nil }
        for element in response.elements {
            if let raw = element.tags?.maxspeed, let kmh = parseMaxSpeed(raw) {
                return kmh
            }
        }
        return nil
    }

    /// Parses OSM's `maxspeed` tag. Handles plain numbers (assumed km/h) and the
    /// "NN mph" form used in the US/UK. Non-numeric values like "walk" or "national"
    /// aren't handled yet and are treated as unknown.
    static func parseMaxSpeed(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.hasSuffix("mph") {
            let numberPart = trimmed.replacingOccurrences(of: "mph", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard let mph = Double(numberPart) else { return nil }
            return mph * 1.60934
        }
        return Double(trimmed)
    }
}
