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
