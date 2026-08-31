//
//  EntryBufferTests.swift
//  RailtownLoggerTests
//

import Foundation
import Testing
@testable import RailtownLogger

@Suite struct EntryBufferTests {
    private func makeEntry(_ message: String) -> LogEntry {
        LogEntry(
            message: message,
            level: .error,
            properties: [:],
            timestamp: Date(timeIntervalSince1970: 0)
        )
    }

    private func drain(_ buffer: EntryBuffer) -> [String] {
        buffer.removeBatch(upTo: .max).map(\.message)
    }

    @Test func appendDropsTheOldestBeyondCapacity() {
        let buffer = EntryBuffer(capacity: 3)
        for name in ["a", "b", "c", "d"] {
            _ = buffer.append(makeEntry(name))
        }

        #expect(drain(buffer) == ["b", "c", "d"])
    }

    /// What the requeue is actually for: a flush cut short puts its batch back at
    /// the front, so those entries go out first on the next attempt.
    @Test func requeuedEntriesReturnToTheFrontWhenThereIsRoom() {
        let buffer = EntryBuffer(capacity: 5)
        _ = buffer.append(makeEntry("new-1"))

        buffer.prepend([makeEntry("in-flight-1"), makeEntry("in-flight-2")])

        #expect(drain(buffer) == ["in-flight-1", "in-flight-2", "new-1"])
    }

    /// The buffer's documented policy is drop-oldest, and a requeued batch *is* the
    /// oldest — so a buffer that filled with newer errors during the flight discards
    /// it rather than evicting entries that arrived since. Deliberate, not a gap in
    /// the rescue: recency wins for error reporting.
    @Test func requeuedEntriesYieldToNewerOnesWhenTheBufferIsFull() {
        let buffer = EntryBuffer(capacity: 5)
        let inFlight = [makeEntry("in-flight-1"), makeEntry("in-flight-2")]

        for index in 1...5 {
            _ = buffer.append(makeEntry("new-\(index)"))
        }

        buffer.prepend(inFlight)

        #expect(drain(buffer) == ["new-1", "new-2", "new-3", "new-4", "new-5"])
    }

    @Test func requeueDropsTheOldestOfAnOversizedBatch() {
        let buffer = EntryBuffer(capacity: 2)
        buffer.prepend([makeEntry("x1"), makeEntry("x2"), makeEntry("x3")])

        #expect(drain(buffer) == ["x2", "x3"])
    }

    @Test func requeueingNothingLeavesTheBufferAlone() {
        let buffer = EntryBuffer(capacity: 3)
        _ = buffer.append(makeEntry("a"))
        buffer.prepend([])

        #expect(drain(buffer) == ["a"])
    }
}
