//
//  TaskSleepTests.swift
//  RailtownLoggerTests
//

import Foundation
import Testing
@testable import RailtownLogger

@Suite struct TaskSleepTests {
    private func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        Task<Never, Never>.nanoseconds(forSeconds: seconds)
    }

    @Test func convertsWholeAndFractionalSeconds() {
        #expect(nanoseconds(1) == 1_000_000_000)
        #expect(nanoseconds(0.05) == 50_000_000)
    }

    /// `UInt64(someNegativeDouble)` traps rather than saturating, so these have to
    /// be filtered before the conversion, not after.
    @Test(arguments: [-1, -0.001, 0] as [TimeInterval])
    func treatsNonPositiveWaitsAsNoWait(_ seconds: TimeInterval) {
        #expect(nanoseconds(seconds) == 0)
    }

    /// NaN fails every comparison, so it must fall through to the zero branch
    /// rather than reaching the conversion.
    @Test func treatsNaNAsNoWait() {
        #expect(nanoseconds(.nan) == 0)
    }

    /// Infinity and greatestFiniteMagnitude overflow `UInt64` nanoseconds; they
    /// clamp instead of trapping.
    @Test(arguments: [Double.infinity, .greatestFiniteMagnitude])
    func clampsWaitsTooLargeToRepresent(_ seconds: TimeInterval) {
        let clamped = nanoseconds(seconds)
        #expect(clamped == UInt64(Task<Never, Never>.maxSleepSeconds * 1_000_000_000))
        #expect(clamped < UInt64.max)
    }

    @Test func sleepsForRoughlyTheRequestedTime() async throws {
        let start = Date()
        try await Task.sleep(seconds: 0.15)
        #expect(Date().timeIntervalSince(start) >= 0.1)
    }
}
