//
//  TaskSleep.swift
//  RailtownLogger
//

import Foundation

extension Task where Success == Never, Failure == Never {
    /// Suspends the current task for `seconds`.
    ///
    /// Stands in for `Task.sleep(for:)`, which needs iOS 16 / macOS 13 while this
    /// package supports iOS 15 / macOS 12. It also absorbs the `UInt64` nanosecond
    /// conversion, which traps on negative, NaN, and overlarge intervals — so
    /// callers can pass a duration straight through without clamping first.
    ///
    /// - Parameter seconds: How long to wait. Non-positive and NaN return immediately.
    static func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: Self.nanoseconds(forSeconds: seconds))
    }

    /// Longest representable wait. Comfortably under the `UInt64` nanosecond
    /// ceiling and far beyond any legitimate one.
    static var maxSleepSeconds: TimeInterval { 1_000_000_000 }

    /// Internal rather than private so the trap-avoidance can be tested directly.
    static func nanoseconds(forSeconds seconds: TimeInterval) -> UInt64 {
        // NaN fails every comparison, so it lands here too.
        guard seconds > 0 else { return 0 }
        return UInt64(min(seconds, maxSleepSeconds) * 1_000_000_000)
    }
}
