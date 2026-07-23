import Foundation
import CoreLocation

// MARK: - Core value types
// These mirror the objects the Node engine produced, now as Swift structs.

/// A hazard severity tier, matching the planner's classification.
enum HazardTier: String, Codable, Sendable {
    case clear
    case caution
    case watch
    case critical
    case unknown

    var label: String {
        switch self {
        case .clear: return "Clear"
        case .caution: return "Caution"
        case .watch: return "Watch"
        case .critical: return "Warning"
        case .unknown: return "Unknown"
        }
    }
}

/// A single active NWS alert whose polygon contains a waypoint at its ETA.
struct HazardAlert: Identifiable, Codable, Sendable {
    let id: String
    let event: String        // "Tornado Warning", "Flash Flood Warning", ...
    let severity: String      // Extreme | Severe | Moderate | Minor
    let headline: String?
    let endsISO: String?
}

/// One sampled point along the route, evaluated against live weather.
struct Waypoint: Identifiable, Sendable {
    let id = UUID()
    let index: Int                 // stable sample order along the route
    let coordinate: CLLocationCoordinate2D
    let cumMiles: Double
    let etaISO: String
    var city: String?
    var state: String?
    var conditions: String
    var temp: Int?
    var windSpeed: String?
    var tier: HazardTier
    var score: Int
    var alert: HazardAlert?

    var eta: Date { ISODate.parse(etaISO) ?? Date() }
}

/// A real point of interest resolved near a stop (gas station, rest area, etc).
struct StopPOI: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let distanceMiles: Double     // from the stop's route point to this POI
    let phone: String?
    let category: String?         // Apple's category label, when available
}

/// A planned fuel or rest stop, possibly nudged off a hazard.
struct PlannedStop: Identifiable, Sendable {
    let id = UUID()
    enum Kind: String, Sendable { case fuel, rest }
    let kind: Kind
    let atMiles: Double
    let etaISO: String
    let city: String?
    let state: String?
    let tier: HazardTier
    let conditions: String
    let nudged: Bool
    let reason: String
    let coordinate: CLLocationCoordinate2D   // carried so the map needn't float-match

    /// The nearest real establishment, filled in by POIService after planning.
    var poi: StopPOI? = nil

    var eta: Date { ISODate.parse(etaISO) ?? Date() }
}

/// The full result of planning a trip.
struct TripPlan: Sendable {
    let distanceMiles: Double
    let durationSec: Double
    let avgSpeedMph: Double
    let routeGeometry: [CLLocationCoordinate2D]
    let waypoints: [Waypoint]
    let stops: [PlannedStop]

    /// Waypoints carrying a critical (life-threatening) warning.
    var criticalWaypoints: [Waypoint] { waypoints.filter { $0.tier == .critical } }
    var watchWaypoints: [Waypoint] { waypoints.filter { $0.tier == .watch } }

    var hasCritical: Bool { !criticalWaypoints.isEmpty }

    /// True when we have usable weather for most of the route. When a trip is
    /// outside NWS coverage (non-US), nearly every waypoint comes back unknown
    /// with "Unknown" conditions — we detect that so the UI can be honest rather
    /// than showing a wall of "Unknown".
    var hasWeatherCoverage: Bool {
        guard !waypoints.isEmpty else { return false }
        let known = waypoints.filter { $0.conditions != "Unknown" && $0.tier != .unknown }
        // Coverage counts if at least a third of waypoints returned real data.
        return Double(known.count) / Double(waypoints.count) >= 0.34
    }
}

/// User-tunable planning parameters (the equivalent of the Node env vars).
struct PlanOptions: Sendable {
    var fuelRangeMiles: Double = 300
    var breakEveryMin: Double = 150
    var sampleIntervalMiles: Double = 25
}
