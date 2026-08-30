import Foundation
import CoreLocation

/// Calls the RoadtripSafety backend instead of hitting OSRM/NWS on-device.
/// Routing, weather, and the nudge algorithm run on the server; this client
/// decodes the finished plan and maps it into the app's existing models. POI
/// resolution still happens on-device afterward (MapKit is device-only).
enum APIClient {

    /// Point this at your deployed server (Render/Railway/Fly). For the
    /// simulator talking to a server on your Mac, use http://localhost:3000.
    static var baseURL = URL(string: "https://roadtrip-safety-engine-3ej7.onrender.com")!

    static let requestTimeout: TimeInterval = 30

    enum APIError: LocalizedError {
        case offline
        case timedOut
        case server(code: String, message: String) // structured error from API
        case badResponse(Int)
        case decoding(String)

        var errorDescription: String? {
            switch self {
            case .offline:
                return "Can't reach the trip service. Check your connection and try again."
            case .timedOut:
                return "The trip service took too long to respond. Try again in a moment."
            case .server(_, let message):
                return message   // already user-friendly
            case .badResponse(let code):
                return "The trip service returned an unexpected response (\(code))."
            case .decoding:
                return "We couldn't read the trip plan. Please try again."
            }
        }
    }

    /// Request a plan from the backend.
    static func plan(origin: CLLocationCoordinate2D,
                     destination: CLLocationCoordinate2D,
                     via: [CLLocationCoordinate2D],
                     departISO: String,
                     options: PlanOptions) async throws -> TripPlan {
        let body = PlanRequest(
            origin: [origin.latitude, origin.longitude],
            destination: [destination.latitude, destination.longitude],
            via: via.map { [$0.latitude, $0.longitude] },
            departISO: departISO,
            options: .init(fuelRangeMiles: options.fuelRangeMiles,
                           breakEveryMin: options.breakEveryMin,
                           sampleInterval: options.sampleIntervalMiles)
        )

        var request = URLRequest(url: baseURL.appendingPathComponent("plan"))
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError {
            switch urlError.code {
            case .timedOut: throw APIError.timedOut
            default: throw APIError.offline
            }
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.badResponse(-1)
        }

        guard (200...299).contains(http.statusCode) else {
            if let apiErr = try? JSONDecoder().decode(APIErrorBody.self, from: data) {
                throw APIError.server(code: apiErr.code ?? "ERROR", message: apiErr.error)
            }
            throw APIError.badResponse(http.statusCode)
        }

        let dto: PlanResponse
        do {
            dto = try JSONDecoder().decode(PlanResponse.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }

        return dto.toTripPlan()
    }
}

// MARK: - Request / response DTOs

private struct PlanRequest: Encodable {
    let origin: [Double]
    let destination: [Double]
    let via: [[Double]]
    let departISO: String
    let options: Options
    struct Options: Encodable {
        let fuelRangeMiles: Double
        let breakEveryMin: Double
        let sampleInterval: Double
    }
}

private struct APIErrorBody: Decodable {
    let error: String
    let code: String?
}

private struct LatLon: Decodable { let lat: Double; let lon: Double }

private struct PlanResponse: Decodable {
    let distanceMiles: Double
    let durationSec: Double
    let avgSpeedMph: Double
    let routeGeometry: [LatLon]
    let waypoints: [WaypointDTO]
    let stops: [StopDTO]

    struct WaypointDTO: Decodable {
        let lat: Double
        let lon: Double
        let cumMiles: Double
        let etaISO: String
        let city: String?
        let state: String?
        let conditions: String
        let temp: Int?
        let windSpeed: String?
        let tier: String
        let score: Int
        let alert: AlertDTO?
    }
    struct AlertDTO: Decodable {
        let event: String
        let severity: String
        let headline: String?
        let endsISO: String?
    }
    struct StopDTO: Decodable {
        let kind: String
        let atMiles: Double
        let etaISO: String
        let city: String?
        let state: String?
        let tier: String
        let conditions: String
        let nudged: Bool
        let reason: String
        let lat: Double?
        let lon: Double?
    }

    func toTripPlan() -> TripPlan {
        let geometry = routeGeometry.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }

        let mappedWaypoints = waypoints.enumerated().map { idx, w -> Waypoint in
            Waypoint(
                index: idx,
                coordinate: CLLocationCoordinate2D(latitude: w.lat, longitude: w.lon),
                cumMiles: w.cumMiles,
                etaISO: w.etaISO,
                city: w.city,
                state: w.state,
                conditions: w.conditions,
                temp: w.temp,
                windSpeed: w.windSpeed,
                tier: HazardTier(rawValue: w.tier) ?? .unknown,
                score: w.score,
                alert: w.alert.map {
                    HazardAlert(id: UUID().uuidString, event: $0.event,
                                severity: $0.severity, headline: $0.headline,
                                endsISO: $0.endsISO)
                }
            )
        }

        let mappedStops = stops.map { s -> PlannedStop in
            let coord = CLLocationCoordinate2D(latitude: s.lat ?? 0, longitude: s.lon ?? 0)
            return PlannedStop(
                kind: s.kind == "fuel" ? .fuel : .rest,
                atMiles: s.atMiles,
                etaISO: s.etaISO,
                city: s.city,
                state: s.state,
                tier: HazardTier(rawValue: s.tier) ?? .clear,
                conditions: s.conditions,
                nudged: s.nudged,
                reason: s.reason,
                coordinate: coord
            )
        }

        return TripPlan(distanceMiles: distanceMiles,
                        durationSec: durationSec,
                        avgSpeedMph: avgSpeedMph,
                        routeGeometry: geometry,
                        waypoints: mappedWaypoints,
                        stops: mappedStops)
    }
}
