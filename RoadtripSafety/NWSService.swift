import Foundation
import CoreLocation

/// Live National Weather Service access: point metadata, hourly forecast, and
/// active alert polygons. Direct port of nws.js. No API key; NWS requires a
/// User-Agent identifying the app.
enum NWSService {

    static let base = "https://api.weather.gov"
    static let userAgent = "roadtrip-safety-app/0.1 (contact: you@example.com)"

    enum NWSError: LocalizedError {
        case offGrid            // 404 — outside US coverage
        case server(Int)
        var errorDescription: String? {
            switch self {
            case .offGrid: return "This location is outside US weather coverage."
            case .server(let c): return "Weather service error (\(c))."
            }
        }
    }

    private static func fetch<T: Decodable>(_ urlStr: String, as type: T.Type, retries: Int = 2) async throws -> T {
        guard let url = URL(string: urlStr) else { throw NWSError.server(-1) }
        var lastStatus = -1
        for attempt in 0...retries {
            var req = URLRequest(url: url)
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("application/geo+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if status == 200 { return try JSONDecoder().decode(T.self, from: data) }
            if status == 404 { throw NWSError.offGrid }
            lastStatus = status
            if attempt < retries {
                try? await Task.sleep(nanoseconds: UInt64(400_000_000 * (attempt + 1)))
            }
        }
        throw NWSError.server(lastStatus)
    }

    // MARK: - Thread-safe cache
    // The planner evaluates waypoints concurrently (4 at a time). Plain static
    // dictionaries are NOT safe for concurrent writes — doing so corrupts their
    // storage and crashes with "unrecognized selector" on a garbage pointer.
    // An actor serializes all access, making concurrent reads/writes safe.
    struct PointMeta: Sendable { let forecastHourly: String; let city: String?; let state: String? }

    private actor Cache {
        var points: [String: PointMeta] = [:]
        var forecasts: [String: (periods: [ForecastPeriod], at: Date)] = [:]
        let forecastTTL: TimeInterval = 600

        func point(_ key: String) -> PointMeta? { points[key] }
        func setPoint(_ key: String, _ meta: PointMeta) { points[key] = meta }

        func forecast(_ key: String) -> [ForecastPeriod]? {
            if let c = forecasts[key], Date().timeIntervalSince(c.at) < forecastTTL {
                return c.periods
            }
            return nil
        }
        func setForecast(_ key: String, _ periods: [ForecastPeriod]) {
            forecasts[key] = (periods, Date())
        }
    }
    private static let cache = Cache()

    static func getPointMeta(_ coord: CLLocationCoordinate2D) async throws -> PointMeta {
        let key = String(format: "%.4f,%.4f", coord.latitude, coord.longitude)
        if let cached = await cache.point(key) { return cached }
        let resp = try await fetch("\(base)/points/\(key)", as: PointsResponse.self)
        let meta = PointMeta(forecastHourly: resp.properties.forecastHourly,
                             city: resp.properties.relativeLocation?.properties.city,
                             state: resp.properties.relativeLocation?.properties.state)
        await cache.setPoint(key, meta)
        return meta
    }

    static func getHourlyForecast(_ coord: CLLocationCoordinate2D) async throws -> (periods: [ForecastPeriod], place: PointMeta) {
        let meta = try await getPointMeta(coord)
        if let cachedPeriods = await cache.forecast(meta.forecastHourly) {
            return (cachedPeriods, meta)
        }
        let resp = try await fetch(meta.forecastHourly, as: ForecastResponse.self)
        await cache.setForecast(meta.forecastHourly, resp.properties.periods)
        return (resp.properties.periods, meta)
    }

    /// Find the forecast period whose [start, end) contains the target time.
    static func forecastAtTime(_ periods: [ForecastPeriod], _ targetISO: String) -> ForecastPeriod? {
        guard let t = ISODate.parse(targetISO)?.timeIntervalSince1970 else { return periods.last }
        for p in periods {
            if let s = ISODate.parse(p.startTime)?.timeIntervalSince1970,
               let e = ISODate.parse(p.endTime)?.timeIntervalSince1970,
               t >= s, t < e { return p }
        }
        return periods.last
    }

    /// Active alerts whose zone contains this point. Each carries a polygon in
    /// `geometry` and event/severity metadata.
    static func getActiveAlerts(_ coord: CLLocationCoordinate2D) async throws -> [AlertFeature] {
        let key = String(format: "%.4f,%.4f", coord.latitude, coord.longitude)
        let resp = try await fetch("\(base)/alerts/active?point=\(key)", as: AlertsResponse.self)
        return resp.features
    }
}

// MARK: - NWS response decoding
struct PointsResponse: Decodable {
    struct Props: Decodable {
        let forecastHourly: String
        let relativeLocation: RelLoc?
    }
    struct RelLoc: Decodable { let properties: RelProps }
    struct RelProps: Decodable { let city: String?; let state: String? }
    let properties: Props
}

struct ForecastResponse: Decodable {
    struct Props: Decodable { let periods: [ForecastPeriod] }
    let properties: Props
}
struct ForecastPeriod: Decodable, Sendable {
    let startTime: String
    let endTime: String
    let temperature: Int?
    let windSpeed: String?
    let shortForecast: String?
}

struct AlertsResponse: Decodable { let features: [AlertFeature] }
struct AlertFeature: Decodable, Sendable {
    let id: String?              // usually present at feature level; tolerate absence
    let geometry: GeoJSONGeometry?
    let properties: AlertProps

    /// A stable identifier even if the feature-level id is missing.
    var stableID: String { id ?? properties.id ?? UUID().uuidString }
}
struct AlertProps: Decodable, Sendable {
    let id: String?
    let event: String
    let severity: String?
    let onset: String?
    let ends: String?
    let expires: String?
    let headline: String?
    let description: String?
}

/// Minimal GeoJSON geometry supporting Polygon and MultiPolygon rings.
struct GeoJSONGeometry: Decodable, Sendable {
    let type: String
    let coordinates: GeoCoordinates
}

/// Coordinates can be [[[Double]]] (Polygon) or [[[[Double]]]] (MultiPolygon).
/// We decode into a nested array of Doubles flexibly.
enum GeoCoordinates: Decodable, Sendable {
    case polygon([[[Double]]])
    case multiPolygon([[[[Double]]]])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let multi = try? container.decode([[[[Double]]]].self) {
            self = .multiPolygon(multi)
        } else if let poly = try? container.decode([[[Double]]].self) {
            self = .polygon(poly)
        } else {
            self = .polygon([])
        }
    }
}
