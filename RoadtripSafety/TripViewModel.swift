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

    // Vehicle type selection
    @Published var vehicleType: VehicleType = .gasoline
    @Published var chargerType: ChargerType = .ccs
    @Published var batteryRange = 280.0

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
        opts.vehicleType = vehicleType
        opts.chargerType = chargerType
        opts.batteryRangeMiles = batteryRange

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

            // ── DEBUG: print the raw plan from the server ────────────────────
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🗺  TRIP PLAN RECEIVED")
            print("   Distance : \(String(format: "%.1f", result.distanceMiles)) mi")
            let hrs = Int(result.durationSec) / 3600
            let mins = (Int(result.durationSec) % 3600) / 60
            print("   Duration : \(hrs)h \(mins)m")
            print("   Avg Speed: \(String(format: "%.1f", result.avgSpeedMph)) mph")
            print("   Route pts: \(result.routeGeometry.count)")
            print("   Vehicle  : \(vehicleType.rawValue)")

            print("\n📍 DESTINATION: \(destName)")
            if let last = result.waypoints.last {
                let loc = last.city.map { "\($0)\(last.state.map { ", \($0)" } ?? "")" } ?? "unknown"
                print("   Location : \(loc)")
                print("   ETA      : \(last.etaISO)")
                print("   Weather  : \(last.conditions) \(last.temp.map { "\($0)°F" } ?? "")")
                print("   Hazard   : \(last.tier.rawValue) (score \(last.score))")
                if let alert = last.alert {
                    print("   ⚠️  Alert  : \(alert.event) — \(alert.severity)")
                    if let hl = alert.headline { print("              \(hl)") }
                }
            }

            print("\n🛑 PLANNED STOPS (\(result.stops.count) total):")
            for (i, stop) in result.stops.enumerated() {
                let loc = stop.city.map { "\($0)\(stop.state.map { ", \($0)" } ?? "")" } ?? "open road"
                let kind = stop.kind == .fuel ? (vehicleType == .electric ? "⚡ Charge" : "⛽ Fuel") : "💤 Rest"
                print("   \(i + 1). \(kind) @ \(String(format: "%.1f", stop.atMiles))mi — \(loc)")
                print("      ETA     : \(stop.etaISO)")
                print("      Weather : \(stop.conditions) | Tier: \(stop.tier)")
                if stop.nudged { print("      ⚡ Nudged: \(stop.reason)") }
                if let net = stop.chargerNetwork { print("      Network : \(net)") }
                if stop.noChargingAvailable { print("      ⚠️  No charging available!") }
            }

            print("\n🌦  WAYPOINTS WITH WEATHER (\(result.waypoints.count) total):")
            for w in result.waypoints {
                let loc = w.city.map { "\($0)\(w.state.map { ", \($0)" } ?? "")" } ?? "–"
                let temp = w.temp.map { "\($0)°F" } ?? "–"
                let wind = w.windSpeed ?? "–"
                print("   \(String(format: "%6.1f", w.cumMiles))mi | \(loc.padding(toLength: 25, withPad: " ", startingAt: 0)) | \(w.conditions.padding(toLength: 12, withPad: " ", startingAt: 0)) | \(temp) | wind \(wind) | \(w.tier.rawValue)")
                if let alert = w.alert {
                    print("           ⚠️  \(alert.event) (\(alert.severity))")
                }
            }
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            // ── END DEBUG ────────────────────────────────────────────────────

            // Show the plan immediately, then resolve real POIs for each stop.
            self.plan = result
            self.isLoading = false

            let enrichedStops = await POIService.enrich(stops: result.stops)

            // ── DEBUG: print enriched POI names ─────────────────────────────
            print("\n📌 ENRICHED STOP POIs:")
            for (i, stop) in enrichedStops.enumerated() {
                let loc = stop.city.map { "\($0)\(stop.state.map { ", \($0)" } ?? "")" } ?? "–"
                print("   \(i + 1). \(stop.kind == .fuel ? (vehicleType == .electric ? "⚡" : "⛽") : "💤") \(loc) @ \(String(format: "%.1f", stop.atMiles))mi")
            }
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            // ── END DEBUG ────────────────────────────────────────────────────

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
