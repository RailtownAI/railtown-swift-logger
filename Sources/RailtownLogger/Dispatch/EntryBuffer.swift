//
//  EntryBuffer.swift
//  RailtownLogger
//

import Foundation

/// Thread-safe staging area for log entries.
///
/// Capture calls append synchronously on their own thread — so an entry is visibly
/// staged before `capture` returns — while ``BatchingDispatcher`` drains batches
/// from the other side.
///
/// - Note: Marked `@unchecked Sendable`. Safety invariant: every access to `entries`
///   happens while holding `lock`, and the lock is never held across a suspension point.
final class EntryBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [LogEntry] = []
    private let capacity: Int

    /// - Parameter capacity: Upper bound on staged entries; the oldest are dropped beyond it.
    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    /// Appends an entry, dropping the oldest ones if the buffer is over capacity.
    /// - Returns: The staged count after the append, and whether anything was dropped.
    func append(_ entry: LogEntry) -> (count: Int, didDrop: Bool) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
        var didDrop = false
        if entries.count > capacity {
            // Newest errors carry the most diagnostic value; sacrifice the oldest.
            entries.removeFirst(entries.count - capacity)
            didDrop = true
        }
        return (entries.count, didDrop)
    }

    /// Puts an undelivered batch back at the front, preserving order.
    ///
    /// Used when a flush is cut short: the batch has already left the buffer, so
    /// without this it would be lost even though it was never sent.
    func prepend(_ batch: [LogEntry]) {
        guard !batch.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        entries.insert(contentsOf: batch, at: 0)
        if entries.count > capacity {
            // Same rule as `append`: oldest first. A requeued batch *is* the oldest,
            // so a buffer that filled with newer errors while it was in flight
            // discards it. That is the documented drop-oldest policy rather than an
            // oversight — for error reporting recency wins, and a batch that already
            // failed to send is often a symptom of the same outage as the newer ones.
            // The requeue earns its place whenever the buffer has room, which is the
            // common case.
            entries.removeFirst(entries.count - capacity)
        }
    }

    /// Removes and returns up to `maxCount` of the oldest entries.
    func removeBatch(upTo maxCount: Int) -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        let batch = Array(entries.prefix(max(0, maxCount)))
        entries.removeFirst(batch.count)
        return batch
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries.isEmpty
    }
}
