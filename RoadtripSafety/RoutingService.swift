import Foundation
import CoreLocation

/// Real driving routes from the public OSRM demo server, plus polyline decoding
/// and ETA-stamped waypoint sampling. Direct port of routing.js.
enum RoutingService {

    static let osrmBase = "https://router.project-osrm.org"

    struct Route {
        let geometry: [CLLocationCoordinate2D]
        let distanceMiles: Double
        let durationSec: Double
    }

    /// A very high ceiling that only catches genuinely absurd results (OSRM
    /// occasionally returns a malformed mega-route). Real intercontinental road
    /// trips — e.g. Algeria to Angola (~4,000 mi) or Portugal to Singapore
    /// (~12,000 mi) — are legitimate, so this is deliberately generous. The real
    /// "is this possible" test is whether OSRM can connect the points by road at
    /// all, not the mileage.
    static let sanityCeilingMiles: Double = 15000

    /// Network timeout for a single routing request.
    static let requestTimeout: TimeInterval = 25

    enum RoutingError: LocalizedError {
        case badResponse(Int)
        case noRoute(String)          // OSRM couldn't connect the two points
        case tooFar(Double)           // beyond even the generous sanity ceiling
        case timedOut
        case offline

        var errorDescription: String? {
            switch self {
            case .badResponse(let code):
                return "The routing service hiccuped (error \(code)). Give it another shot in a moment."
            case .noRoute:
                return "There's no road connecting these two places. Unless you've got a car that swims, this one's not happening. 🚗🌊"
            case .tooFar:
                return "That route is longer than any drivable trip on Earth — something looks off with those locations. Double-check them and try again."
            case .timedOut:
                return "The routing service took too long to answer. Long international routes can be slow — try again in a few seconds."
            case .offline:
                return "Can't reach the routing service. Check your internet connection and try again."
            }
        }
    }

    /// Decode an OSRM/Google encoded polyline (precision 5) into coordinates.
    static func decodePolyline(_ str: String, precision: Double = 5) -> [CLLocationCoordinate2D] {
        var index = str.startIndex
        var lat = 0.0, lng = 0.0
        var coords: [CLLocationCoordinate2D] = []
        let factor = pow(10.0, precision)

        func nextValue() -> Int {
            var result = 1, shift = 0, b: Int
            repeat {
                b = Int(str[index].asciiValue ?? 0) - 63 - 1
                index = str.index(after: index)
                result += b << shift
                shift += 5
            } while b >= 0x1f
            return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
        }

        while index < str.endIndex {
            lat += Double(nextValue())
            lng += Double(nextValue())
            coords.append(CLLocationCoordinate2D(latitude: lat / factor,
                                                 longitude: lng / factor))
        }
        return coords
    }

    /// Haversine distance in miles.
    static func haversineMiles(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let R = 3958.8
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * R * asin(sqrt(h))
    }

    /// Fetch a real driving route. Coordinates in (lat, lon); OSRM wants lon,lat.
    static func getRoute(origin: CLLocationCoordinate2D,
                         destination: CLLocationCoordinate2D) async throws -> Route {
        try await getRoute(waypoints: [origin, destination])
    }

    /// Fetch a route through an ordered list of waypoints (origin, any number of
    /// intermediate stops the user added, then destination). OSRM strings them
    /// together with semicolons and routes through each in order.
    static func getRoute(waypoints: [CLLocationCoordinate2D]) async throws -> Route {
        guard waypoints.count >= 2 else { throw RoutingError.noRoute("need 2+ points") }

        let coords = waypoints
            .map { "\($0.longitude),\($0.latitude)" }
            .joined(separator: ";")
        let urlStr = "\(osrmBase)/route/v1/driving/\(coords)?overview=full&geometries=polyline&annotations=duration,distance"
        guard let url = URL(string: urlStr) else { throw RoutingError.noRoute("bad url") }

        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError {
            switch urlError.code {
            case .timedOut: throw RoutingError.timedOut
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .dataNotAllowed:
                throw RoutingError.offline
            default: throw RoutingError.offline
            }
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RoutingError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let decoded = try JSONDecoder().decode(OSRMResponse.self, from: data)

        // OSRM signals an unroutable pair (e.g. across an ocean) with a non-"Ok"
        // code or an empty routes array. THIS is the real "is a road trip
        // possible" test — road connectivity, not mileage.
        guard decoded.code == "Ok", let route = decoded.routes.first else {
            throw RoutingError.noRoute(decoded.code)
        }

        let distanceMiles = route.distance / 1609.34
        // Only reject genuinely absurd results (malformed mega-routes).
        if distanceMiles > sanityCeilingMiles {
            throw RoutingError.tooFar(distanceMiles)
        }

        return Route(geometry: decodePolyline(route.geometry),
                     distanceMiles: distanceMiles,
                     durationSec: route.duration)
    }

    /// A sampled point along the route, before weather evaluation.
    struct SampledPoint: Sendable {
        let index: Int
        let coord: CLLocationCoordinate2D
        let cumMiles: Double
        let etaISO: String
    }

    /// Walk the route and emit a waypoint every `intervalMiles`, each stamped
    /// with an ETA derived from departure + route average speed.
    static func sampleRoute(_ route: Route,
                            departISO: String,
                            intervalMiles: Double = 25) -> (waypoints: [SampledPoint], avgSpeedMph: Double) {
        let geom = route.geometry
        guard geom.count > 1, route.durationSec > 0 else {
            // Degenerate route: emit whatever single point we have.
            let depart = ISODate.parse(departISO) ?? Date()
            let pts = geom.first.map {
                [SampledPoint(index: 0, coord: $0, cumMiles: 0, etaISO: ISODate.string(from: depart))]
            } ?? []
            return (pts, 1)
        }

        let avgSpeedMph = route.distanceMiles / (route.durationSec / 3600)
        let depart = ISODate.parse(departISO) ?? Date()

        var out: [SampledPoint] = []
        var cumMiles = 0.0
        var lastSampled = 0.0
        var idx = 0

        out.append(SampledPoint(index: idx, coord: geom[0], cumMiles: 0,
                                etaISO: ISODate.string(from: depart)))
        idx += 1

        for i in 1..<geom.count {
            cumMiles += haversineMiles(geom[i - 1], geom[i])
            if cumMiles - lastSampled >= intervalMiles {
                let driveHours = cumMiles / avgSpeedMph
                let eta = depart.addingTimeInterval(driveHours * 3600)
                out.append(SampledPoint(index: idx, coord: geom[i],
                                        cumMiles: (cumMiles * 10).rounded() / 10,
                                        etaISO: ISODate.string(from: eta)))
                idx += 1
                lastSampled = cumMiles
            }
        }

        // Always include the destination as the final waypoint.
        let last = geom[geom.count - 1]
        let eta = depart.addingTimeInterval(route.durationSec)
        out.append(SampledPoint(index: idx, coord: last,
                                cumMiles: (route.distanceMiles * 10).rounded() / 10,
                                etaISO: ISODate.string(from: eta)))

        return (out, avgSpeedMph)
    }
}

// MARK: - OSRM response decoding
private struct OSRMResponse: Decodable {
    let code: String
    let routes: [OSRMRoute]
}
private struct OSRMRoute: Decodable {
    let geometry: String
    let distance: Double
    let duration: Double
}
