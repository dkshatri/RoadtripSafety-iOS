import Foundation

/// NWS and OSRM return ISO-8601 timestamps that sometimes include fractional
/// seconds and always include a timezone offset. The stock ISO8601DateFormatter
/// fails when the format doesn't exactly match its options, which would silently
/// break time-to-forecast matching. This helper tries both variants.
enum ISODate {
    private static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ s: String) -> Date? {
        withFractional.date(from: s) ?? plain.date(from: s)
    }

    static func string(from date: Date) -> String {
        plain.string(from: date)
    }
}
