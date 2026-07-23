import Foundation
import MapKit

/// Resolves a `PlannedStop`'s route coordinate to a real nearby establishment
/// using MapKit local search. Fuel stops use the precise gas-station POI
/// category; rest stops use a natural-language query since Apple has no single
/// "rest area" category.
///
/// Main-actor isolated: `MKLocalSearch` is a UIKit-adjacent API and expects to
/// be driven from the main actor.
@MainActor
enum POIService {

    /// Search radius around the stop's route point. Stops are placed on the
    /// route line, and real services cluster near exits, so a few miles covers it.
    static let searchRadiusMeters: CLLocationDistance = 8_000  // ~5 miles

    /// Resolve the single best POI for one stop. Returns nil if nothing is found
    /// (rural stretch) — the stop is still valid, just unnamed.
    static func resolvePOI(for stop: PlannedStop) async -> StopPOI? {
        let center = stop.coordinate
        let region = MKCoordinateRegion(center: center,
                                        latitudinalMeters: searchRadiusMeters,
                                        longitudinalMeters: searchRadiusMeters)

        let items: [MKMapItem]
        do {
            switch stop.kind {
            case .fuel:
                items = try await categorySearch(categories: [.gasStation], region: region)
            case .rest:
                // Rest areas + a fallback to broader stop-friendly categories.
                var found = try await naturalLanguageSearch(query: "rest area", region: region)
                if found.isEmpty {
                    found = try await categorySearch(categories: [.gasStation, .cafe, .restaurant],
                                                     region: region)
                }
                items = found
            }
        } catch {
            return nil
        }

        // Pick the closest result to the stop's route point.
        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let nearest = items.min { a, b in
            distance(origin, a) < distance(origin, b)
        }
        guard let item = nearest else { return nil }

        let meters = distance(origin, item)
        return StopPOI(name: item.name ?? "Unnamed stop",
                       coordinate: item.placemark.coordinate,
                       distanceMiles: meters / 1609.34,
                       phone: item.phoneNumber,
                       category: item.pointOfInterestCategory?.friendlyName)
    }

    /// Resolve POIs for every stop concurrently, returning stops with `.poi` set.
    static func enrich(stops: [PlannedStop]) async -> [PlannedStop] {
        await withTaskGroup(of: (Int, StopPOI?).self) { group -> [PlannedStop] in
            for (i, stop) in stops.enumerated() {
                group.addTask { (i, await resolvePOI(for: stop)) }
            }
            var result = stops
            for await (i, poi) in group {
                result[i].poi = poi
            }
            return result
        }
    }

    // MARK: - Search variants

    private static func categorySearch(categories: [MKPointOfInterestCategory],
                                       region: MKCoordinateRegion) async throws -> [MKMapItem] {
        let request = MKLocalPointsOfInterestRequest(coordinateRegion: region)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        return response.mapItems
    }

    private static func naturalLanguageSearch(query: String,
                                              region: MKCoordinateRegion) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        return response.mapItems
    }

    private static func distance(_ origin: CLLocation, _ item: MKMapItem) -> CLLocationDistance {
        let c = item.placemark.coordinate
        return origin.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
    }
}

// MARK: - Friendly category labels
extension MKPointOfInterestCategory {
    var friendlyName: String {
        switch self {
        case .gasStation: return "Gas station"
        case .cafe: return "Café"
        case .restaurant: return "Restaurant"
        case .evCharger: return "EV charging"
        case .parking: return "Parking"
        default: return "Stop"
        }
    }
}
