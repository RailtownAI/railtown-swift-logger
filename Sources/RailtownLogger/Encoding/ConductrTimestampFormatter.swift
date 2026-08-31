//
//  ConductrTimestampFormatter.swift
//  RailtownLogger
//

import Foundation

/// Renders timestamps in the shape the Conductr backend expects.
protocol TimestampFormatting: Sendable {
    func string(from date: Date) -> String
}

/// Produces .NET `DateTimeOffset`-style strings, e.g. `2026-08-18T16:26:20.0862000+00:00`
/// (UTC, seven fractional digits, explicit offset). `ISO8601DateFormatter` cannot emit
/// this shape, hence a fixed-format `DateFormatter`.
///
/// - Note: Marked `@unchecked Sendable`. Safety invariant: `DateFormatter` is documented
///   thread-safe for *formatting* on all supported OS versions; this instance is fully
///   configured in `init` and never mutated afterwards.
struct ConductrTimestampFormatter: TimestampFormatting, @unchecked Sendable {
    private let formatter: DateFormatter

    init() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSxxx"
        self.formatter = formatter
    }

    func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}
