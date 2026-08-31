//
//  RailtownMessage.swift
//  RailtownLogger
//

/// A log message whose interpolated values are quoted automatically:
/// `"Flow \(title) failed"` renders as `Flow 'Math Flow' failed`.
///
/// String literals convert as-is, so call sites read like plain strings. Numeric
/// interpolations stay bare (`"Sent \(3) items"` → `Sent 3 items`), optionals render
/// their wrapped value or a bare `nil` (`"User \(name)"` → `User 'Bob'` / `User nil`),
/// and `\(raw:)` opts any value out of quoting — including whole prebuilt `String`s:
/// `log("\(raw: prebuiltMessage)")`.
public struct RailtownMessage: ExpressibleByStringInterpolation, Sendable {
    public struct StringInterpolation: StringInterpolationProtocol {
        var output = ""

        public init(literalCapacity: Int, interpolationCount: Int) {
            output.reserveCapacity(literalCapacity + interpolationCount * 8)
        }

        public mutating func appendLiteral(_ literal: String) {
            output.append(literal)
        }

        /// Interpolated values are wrapped in single quotes.
        public mutating func appendInterpolation<T>(_ value: T) {
            output.append("'\(value)'")
        }

        /// Numbers read better bare: `\(count)` → `3`, not `"3"`.
        public mutating func appendInterpolation<T: Numeric>(_ value: T) {
            output.append("\(value)")
        }

        /// Optionals render their wrapped value, never `Optional("…")`; an empty
        /// optional renders as a bare `nil`, distinguishing an absent value from
        /// the literal string `'nil'`.
        ///
        /// Wins over the unconstrained overload above for optional arguments: both
        /// are exact matches, and Swift's tiebreak ranks `T?` as more specialized.
        /// Non-optional arguments still take the overload above, which is the exact
        /// match there. Unwraps one level only — `String??` still renders `Optional(…)`.
        public mutating func appendInterpolation<T>(_ value: T?) {
            guard let value else {
                output.append("nil")
                return
            }
            output.append("'\(value)'")
        }

        /// Numeric optionals stay bare, matching the non-optional case.
        public mutating func appendInterpolation<T: Numeric>(_ value: T?) {
            guard let value else {
                output.append("nil")
                return
            }
            output.append("\(value)")
        }

        /// Explicit opt-out from quoting for any value: `\(raw: value)`.
        public mutating func appendInterpolation<T>(raw value: T) {
            output.append("\(value)")
        }

        /// `\(raw:)` on an optional unwraps rather than printing `Optional("…")`.
        public mutating func appendInterpolation<T>(raw value: T?) {
            guard let value else {
                output.append("nil")
                return
            }
            output.append("\(value)")
        }
    }

    /// The rendered text uploaded as the event's `Message`.
    public let rendered: String

    public init(stringLiteral value: String) {
        rendered = value
    }

    public init(stringInterpolation: StringInterpolation) {
        rendered = stringInterpolation.output
    }
}
