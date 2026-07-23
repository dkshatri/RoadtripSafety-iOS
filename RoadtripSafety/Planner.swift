import Foundation
import CoreLocation

/// The differentiator, ported from planner.js: evaluate each waypoint against
/// live weather + alert polygons, then place fuel/rest stops and nudge them off
/// hazard waypoints onto the nearest clear point in range.
enum Planner {

    static let criticalEvents: Set<String> = [
        "Tornado Warning", "Hurricane Warning", "Flash Flood Warning",
        "Extreme Wind Warning", "Severe Thunderstorm Warning"
    ]
    static let watchEvents: Set<String> = [
        "Tornado Watch", "Flash Flood Watch", "Severe Thunderstorm Watch",
        "Hurricane Watch", "Flood Watch", "Wind Advisory", "Winter Weather Advisory"
    ]

    // MARK: - Point in polygon (ray casting). GeoJSON rings are [lon, lat].
    static func pointInRing(lon: Double, lat: Double, ring: [[Double]]) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            guard ring[i].count >= 2, ring[j].count >= 2 else { j = i; continue }
            let xi = ring[i][0], yi = ring[i][1]
            let xj = ring[j][0], yj = ring[j][1]
            let intersect = (yi > lat) != (yj > lat) &&
                lon < (xj - xi) * (lat - yi) / (yj - yi) + xi
            if intersect { inside.toggle() }
            j = i
        }
        return inside
    }

    static func pointInGeometry(lon: Double, lat: Double, geometry: GeoJSONGeometry?) -> Bool {
        guard let geometry = geometry else { return false }
        switch geometry.coordinates {
        case .polygon(let rings):
            guard let outer = rings.first else { return false }
            return pointInRing(lon: lon, lat: lat, ring: outer)
        case .multiPolygon(let polys):
            return polys.contains { poly in
                guard let outer = poly.first else { return false }
                return pointInRing(lon: lon, lat: lat, ring: outer)
            }
        }
    }

    // MARK: - Forecast hazard score (0 fine .. 3 dangerous) from plain text.
    static func scoreForecast(_ period: ForecastPeriod?) -> Int {
        let f = (period?.shortForecast ?? "").lowercased()
        // Wind strings look like "10 mph" or "10 to 20 mph"; take the HIGHEST
        // number present so a gust range isn't understated.
        let wind = (period?.windSpeed ?? "0")
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }
            .max() ?? 0
        var score = 0
        if f.contains("thunderstorm") || f.contains("hail") { score = max(score, 2) }
        if f.contains("heavy rain") || f.contains("freezing") || f.contains("ice")
            || f.contains("blizzard") || f.contains("snow") { score = max(score, 2) }
        if f.contains("rain") || f.contains("showers") || f.contains("fog") { score = max(score, 1) }
        if wind >= 35 { score = max(score, 2) } else if wind >= 25 { score = max(score, 1) }
        return score
    }

    // MARK: - Evaluate one waypoint against live data.
    static func evaluateWaypoint(index: Int,
                                 coord: CLLocationCoordinate2D,
                                 cumMiles: Double,
                                 etaISO: String) async -> Waypoint {
        async let forecastResult = try? NWSService.getHourlyForecast(coord)
        async let alertsResult = try? NWSService.getActiveAlerts(coord)
        let forecast = await forecastResult
        let alerts = (await alertsResult) ?? []

        let period = forecast.flatMap { NWSService.forecastAtTime($0.periods, etaISO) }
        let etaMs = ISODate.parse(etaISO)?.timeIntervalSince1970 ?? 0

        // Keep alerts whose polygon contains this point and whose window overlaps ETA.
        let activeHere = alerts.filter { a in
            let inPoly = a.geometry != nil
                ? pointInGeometry(lon: coord.longitude, lat: coord.latitude, geometry: a.geometry)
                : true
            guard inPoly else { return false }
            let onset = a.properties.onset.flatMap { ISODate.parse($0)?.timeIntervalSince1970 } ?? -.infinity
            let ends = (a.properties.ends ?? a.properties.expires)
                .flatMap { ISODate.parse($0)?.timeIntervalSince1970 } ?? .infinity
            return etaMs >= onset - 3600 && etaMs <= ends
        }

        var tier: HazardTier = .clear
        var score = scoreForecast(period)
        var headline: HazardAlert?

        for a in activeHere {
            let ev = a.properties.event
            if criticalEvents.contains(ev) || a.properties.severity == "Extreme" {
                tier = .critical; score = 3
                headline = HazardAlert(id: a.stableID, event: ev,
                                       severity: a.properties.severity ?? "",
                                       headline: a.properties.headline,
                                       endsISO: a.properties.ends ?? a.properties.expires)
                break
            } else if watchEvents.contains(ev) || a.properties.severity == "Severe" {
                if tier != .critical {
                    tier = .watch; score = max(score, 2)
                    headline = HazardAlert(id: a.stableID, event: ev,
                                           severity: a.properties.severity ?? "",
                                           headline: a.properties.headline,
                                           endsISO: a.properties.ends ?? a.properties.expires)
                }
            }
        }
        if tier == .clear && score >= 2 { tier = .caution }

        let place = forecast?.place
        return Waypoint(index: index, coordinate: coord, cumMiles: cumMiles, etaISO: etaISO,
                        city: place?.city, state: place?.state,
                        conditions: period?.shortForecast ?? "Unknown",
                        temp: period?.temperature, windSpeed: period?.windSpeed,
                        tier: tier, score: score, alert: headline)
    }

    // MARK: - The nudge: place stops by range/cadence, move off hazards.
    static func planStops(_ evaluated: [Waypoint], options: PlanOptions, avgSpeedMph: Double) -> [PlannedStop] {
        guard let last = evaluated.last else { return [] }
        let totalMiles = last.cumMiles
        let breakEveryMiles = (options.breakEveryMin / 60) * avgSpeedMph
        var stops: [PlannedStop] = []

        func nudge(idealMiles: Double, kind: PlannedStop.Kind) -> PlannedStop? {
            let window = 40.0
            var candidates = evaluated.filter {
                $0.cumMiles >= idealMiles - window && $0.cumMiles <= idealMiles + window
            }
            if candidates.isEmpty {
                if let nearest = evaluated.min(by: {
                    abs($0.cumMiles - idealMiles) < abs($1.cumMiles - idealMiles)
                }) { candidates = [nearest] } else { return nil }
            }

            let chosen = candidates.sorted {
                if $0.score != $1.score { return $0.score < $1.score }
                return abs($0.cumMiles - idealMiles) < abs($1.cumMiles - idealMiles)
            }.first!

            // The "naive" stop is the one closest to the ideal mile ignoring
            // weather — what a range-only planner would pick.
            let naive = candidates.min {
                abs($0.cumMiles - idealMiles) < abs($1.cumMiles - idealMiles)
            }!

            let nudged = chosen.cumMiles != naive.cumMiles && naive.score > chosen.score
            var reason: String
            if nudged {
                let dir = chosen.cumMiles < naive.cumMiles ? "earlier" : "later"
                let miles = abs(Int((chosen.cumMiles - naive.cumMiles).rounded()))
                let hazardText = naive.alert?.event.lowercased() ?? naive.conditions.lowercased()
                let place = naive.city ?? "the default stop"
                reason = kind == .fuel
                    ? "Fuel up \(miles) mi \(dir) than usual — \(place) has \(hazardText) at your ETA"
                    : "Take your break \(dir) — \(place) is under \(hazardText) when you'd pass through"
            } else if chosen.score >= 2 {
                reason = "Unavoidable rough weather near here (\(chosen.conditions)); no clear window in range — consider delaying departure"
            } else {
                let place = chosen.city ?? "waypoint"
                reason = kind == .fuel
                    ? "Fuel stop near \(place) — clear conditions, on-range"
                    : "Rest break near \(place) — clear conditions"
            }

            return PlannedStop(kind: kind, atMiles: chosen.cumMiles, etaISO: chosen.etaISO,
                               city: chosen.city, state: chosen.state, tier: chosen.tier,
                               conditions: chosen.conditions, nudged: nudged, reason: reason,
                               coordinate: chosen.coordinate)
        }

        var nextFuel = options.fuelRangeMiles
        while nextFuel < totalMiles {
            if let s = nudge(idealMiles: nextFuel, kind: .fuel) { stops.append(s) }
            nextFuel += options.fuelRangeMiles
        }
        var nextBreak = breakEveryMiles
        while nextBreak < totalMiles {
            if let s = nudge(idealMiles: nextBreak, kind: .rest) { stops.append(s) }
            nextBreak += breakEveryMiles
        }

        return stops.sorted { $0.atMiles < $1.atMiles }
    }

    // MARK: - Full pipeline.
    static func planTrip(origin: CLLocationCoordinate2D,
                         destination: CLLocationCoordinate2D,
                         via: [CLLocationCoordinate2D] = [],
                         departISO: String,
                         options: PlanOptions = PlanOptions()) async throws -> TripPlan {
        // Build the ordered waypoint list: origin, any user-added stops, destination.
        let allPoints = [origin] + via + [destination]
        let route = try await RoutingService.getRoute(waypoints: allPoints)
        let sampled = RoutingService.sampleRoute(route, departISO: departISO,
                                                 intervalMiles: options.sampleIntervalMiles)

        // Evaluate waypoints with bounded concurrency (be polite to free APIs).
        var evaluated: [Waypoint] = []
        let batchSize = 4
        var i = 0
        while i < sampled.waypoints.count {
            let batch = Array(sampled.waypoints[i..<min(i + batchSize, sampled.waypoints.count)])
            let results = await withTaskGroup(of: Waypoint.self) { group -> [Waypoint] in
                for wp in batch {
                    group.addTask {
                        await evaluateWaypoint(index: wp.index, coord: wp.coord,
                                               cumMiles: wp.cumMiles, etaISO: wp.etaISO)
                    }
                }
                var acc: [Waypoint] = []
                for await r in group { acc.append(r) }
                return acc
            }
            evaluated.append(contentsOf: results)
            i += batchSize
        }
        // Sort by the stable sample index, not by mileage (which can tie).
        evaluated.sort { $0.index < $1.index }

        let stops = planStops(evaluated, options: options, avgSpeedMph: sampled.avgSpeedMph)
        return TripPlan(distanceMiles: route.distanceMiles, durationSec: route.durationSec,
                        avgSpeedMph: sampled.avgSpeedMph, routeGeometry: route.geometry,
                        waypoints: evaluated, stops: stops)
    }
}
