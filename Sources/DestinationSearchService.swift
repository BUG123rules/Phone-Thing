import MapKit
import Combine

/// Wraps `MKLocalSearchCompleter` for Apple-Maps-style search-as-you-type suggestions,
/// biased toward the current location, and resolves a chosen suggestion into a full
/// `MKMapItem` for routing.
final class DestinationSearchService: NSObject, ObservableObject {
    @Published var query: String = "" {
        didSet { completer.queryFragment = query }
    }
    @Published private(set) var suggestions: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()
    private var locationCancellable: AnyCancellable?

    init(locationProvider: LocationSpeedProvider) {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]

        locationCancellable = locationProvider.$lastLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                self?.completer.region = MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: 50_000,
                    longitudinalMeters: 50_000
                )
            }
    }

    func resolve(_ completion: MKLocalSearchCompletion, onResolve: @escaping (MKMapItem?) -> Void) {
        let request = MKLocalSearch.Request(completion: completion)
        MKLocalSearch(request: request).start { response, _ in
            DispatchQueue.main.async {
                onResolve(response?.mapItems.first)
            }
        }
    }
}

extension DestinationSearchService: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }
}
