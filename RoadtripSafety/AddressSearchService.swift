import Foundation
import MapKit
import Combine

/// Live address/city autocomplete via MKLocalSearchCompleter, plus resolution
/// of a chosen suggestion to coordinates. Main-actor isolated since MapKit's
/// search APIs expect the main thread.
@MainActor
final class AddressSearchService: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {

    @Published var suggestions: [MKLocalSearchCompletion] = []
    @Published var query: String = "" {
        didSet { completer.queryFragment = query }
    }

    private let completer: MKLocalSearchCompleter

    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        // Cover addresses and points of interest (cities, landmarks, streets).
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in self.suggestions = results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.suggestions = [] }
    }

    func clear() {
        query = ""
        suggestions = []
    }

    /// Resolve a chosen completion to a coordinate + a clean display name.
    func resolve(_ completion: MKLocalSearchCompletion) async -> (coordinate: CLLocationCoordinate2D, name: String)? {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start(),
              let item = response.mapItems.first else { return nil }
        let coord = item.placemark.coordinate
        let name = item.name ?? completion.title
        return (coord, name)
    }

    /// Resolve a free-typed string (fallback when the user doesn't tap a suggestion).
    func geocode(_ text: String) async -> (coordinate: CLLocationCoordinate2D, name: String)? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start(),
              let item = response.mapItems.first else { return nil }
        return (item.placemark.coordinate, item.name ?? text)
    }
}
