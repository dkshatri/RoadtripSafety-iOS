import Foundation
import CoreLocation
import SwiftUI

/// Drives the planning screen: holds inputs, calls the backend via `APIClient`, and
/// publishes the result (or error) for the views.
@MainActor
final class TripViewModel: ObservableObject {
    // Display names shown in the fields.
    @Published var originName = ""
    @Published var destName = ""
    // Resolved coordinates, set when the user picks a suggestion (or via geocode).
    @Published var originCoord: CLLocationCoordinate2D?
    @Published var destCoord: CLLocationCoordinate2D?

    @Published var departureDate = Date()
    @Published var fuelRange = 300.0
    @Published var breakEvery = 150.0

    /// User-added intermediate stops the route must pass through, in order.
    @Published var customStops: [CustomStop] = []

    // Output state.
    @Published var plan: TripPlan?
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// A stop the user explicitly wants on the route.
    struct CustomStop: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var coordinate: CLLocationCoordinate2D

        static func == (lhs: CustomStop, rhs: CustomStop) -> Bool { lhs.id == rhs.id }
    }

    func addCustomStop(name: String, coordinate: CLLocationCoordinate2D) {
        customStops.append(CustomStop(name: name, coordinate: coordinate))
    }

    func removeCustomStop(_ stop: CustomStop) {
        customStops.removeAll { $0.id == stop.id }
    }

    // Fallback geocoder for free-typed text the user didn't pick from suggestions.
    private let geocoder = AddressSearchService()

    func runPlan() async {
        // Resolve origin: prefer a picked coordinate, else geocode the typed text.
        var origin = originCoord
        if origin == nil, !originName.isEmpty {
            origin = (await geocoder.geocode(originName))?.coordinate
        }
        guard let origin else {
            errorMessage = originName.isEmpty
                ? "Enter a starting city or address."
                : "Couldn't find \"\(originName)\". Try a more specific place or pick one from the suggestions."
            return
        }

        var dest = destCoord
        if dest == nil, !destName.isEmpty {
            dest = (await geocoder.geocode(destName))?.coordinate
        }
        guard let dest else {
            errorMessage = destName.isEmpty
                ? "Enter a destination city or address."
                : "Couldn't find \"\(destName)\". Try a more specific place or pick one from the suggestions."
            return
        }

        isLoading = true
        errorMessage = nil
        plan = nil
        // Whatever happens below, never leave the UI stuck on the loading screen.
        defer { isLoading = false }

        let departISO = ISODate.string(from: departureDate)
        var opts = PlanOptions()
        opts.fuelRangeMiles = fuelRange
        opts.breakEveryMin = breakEvery

        do {
            // The backend does routing + weather + the nudge algorithm and
            // returns a finished plan. POI names are still resolved on-device
            // afterward (MapKit is device-only).
            let via = customStops.map { $0.coordinate }
            let result = try await APIClient.plan(origin: origin, destination: dest,
                                                  via: via, departISO: departISO,
                                                  options: opts)

            // Guard against a degenerate plan (no usable waypoints).
            guard !result.waypoints.isEmpty else {
                errorMessage = "We couldn't read the weather along this route. Try again shortly."
                return
            }

            // Show the plan immediately, then resolve real POIs for each stop.
            // MKLocalSearch is main-actor work, so it runs here, after the
            // detached compute. The map/timeline update again when it completes.
            self.plan = result
            self.isLoading = false

            let enrichedStops = await POIService.enrich(stops: result.stops)
            self.plan = TripPlan(distanceMiles: result.distanceMiles,
                                 durationSec: result.durationSec,
                                 avgSpeedMph: result.avgSpeedMph,
                                 routeGeometry: result.routeGeometry,
                                 waypoints: result.waypoints,
                                 stops: enrichedStops)
            return
        } catch let apiError as APIClient.APIError {
            // The API's messages are already user-friendly (including the
            // impossible-route and offline cases).
            errorMessage = apiError.errorDescription
        } catch {
            errorMessage = "Something went wrong planning this trip. Please try again."
        }
    }
}

// MARK: - Shared UI helpers

extension HazardTier {
    var color: Color {
        switch self {
        case .critical: return .red
        case .watch: return .orange
        case .caution: return .yellow
        case .clear: return .green
        case .unknown: return .gray
        }
    }
    var systemIcon: String {
        switch self {
        case .critical: return "exclamationmark.triangle.fill"
        case .watch: return "exclamationmark.circle.fill"
        case .caution: return "cloud.rain.fill"
        case .clear: return "sun.max.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

func shortTime(_ iso: String) -> String {
    guard let d = ISODate.parse(iso) else { return "" }
    let f = DateFormatter()
    f.dateFormat = "h:mm a"
    return f.string(from: d)
}
