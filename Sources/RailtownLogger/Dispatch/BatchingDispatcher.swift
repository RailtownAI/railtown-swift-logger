//
//  BatchingDispatcher.swift
//  RailtownLogger
//

import Foundation

/// Accepts log entries and delivers them to Conductr in batches.
protocol LogDispatching: Sendable {
    /// Stages an entry for upload. Synchronous, so capture sites never wait on delivery,
    /// and the entry is guaranteed staged before the call returns.
    func stage(_ entry: LogEntry)

    /// Delivers everything staged, waiting for completion — including retries.
    func flush() async
}

/// Actor owning all delivery state.
///
/// Delivery triggers: the buffer reaching `maxBatchSize`, `flushInterval` elapsing since
/// an entry was staged into an idle buffer, or an explicit ``flush()``. Retryable failures
/// (408/429/5xx/transport errors) back off exponentially up to the policy's attempt cap;
/// terminal responses (other 4xx) drop the batch immediately.
actor BatchingDispatcher: LogDispatching {
    /// Upper bound on `flushInterval`. The timer converts it to nanoseconds as a `UInt64`,
    /// so anything above ~1.8e10 seconds overflows that conversion and traps — an
    /// uncatchable crash inside the timer task, well away from the call that configured it.
    /// A day is far below the overflow threshold and far above any useful batching window.
    private static let maxFlushInterval: TimeInterval = 86_400

    private let buffer: EntryBuffer
    private let credentials: RailtownCredentials
    private let flushInterval: TimeInterval
    private let maxBatchSize: Int
    private let retryPolicy: RetryPolicy
    private let payloadBuilder: any PayloadBuilding
    private let httpClient: any HTTPClient
    private let internalLog: InternalLog

    private var timerTask: Task<Void, Never>?
    private var drainTask: Task<Void, Never>?

    init(
        credentials: RailtownCredentials,
        flushInterval: TimeInterval,
        maxBatchSize: Int,
        maxBufferedEntries: Int,
        retryPolicy: RetryPolicy,
        payloadBuilder: any PayloadBuilding,
        httpClient: any HTTPClient,
        internalLog: InternalLog
    ) {
        self.buffer = EntryBuffer(capacity: maxBufferedEntries)
        self.credentials = credentials
        // `max` returns its first argument when the second is NaN, so NaN lands on 0 here
        // rather than propagating into the timer.
        let clampedInterval = min(max(0, flushInterval), Self.maxFlushInterval)
        if clampedInterval != flushInterval {
            internalLog.warning(
                "flushInterval \(flushInterval) is out of range — using \(clampedInterval)."
            )
        }
        self.flushInterval = clampedInterval
        self.maxBatchSize = max(1, maxBatchSize)
        self.retryPolicy = retryPolicy
        self.payloadBuilder = payloadBuilder
        self.httpClient = httpClient
        self.internalLog = internalLog
    }

    nonisolated func stage(_ entry: LogEntry) {
        let (count, didDrop) = buffer.append(entry)
        if didDrop {
            internalLog.warning("Log buffer is full — dropped the oldest entry.")
        }
        // Only the first entry (timer arming) and a full batch (immediate drain)
        // change scheduling; intermediate entries ride along.
        guard count == 1 || count >= maxBatchSize else { return }
        Task { await self.entryStaged(count: count) }
    }

    func flush() async {
        startDrainIfNeeded()
        while let activeDrain = drainTask {
            await activeDrain.value
        }
    }

    // MARK: - Scheduling (actor-isolated)

    private func entryStaged(count: Int) {
        if count >= maxBatchSize {
            startDrainIfNeeded()
        } else {
            scheduleTimerIfNeeded()
        }
    }

    private func scheduleTimerIfNeeded() {
        guard timerTask == nil, drainTask == nil, !buffer.isEmpty else { return }
        timerTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(flushInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.timerDidFire()
        }
    }

    private func timerDidFire() {
        timerTask = nil
        startDrainIfNeeded()
    }

    private func startDrainIfNeeded() {
        timerTask?.cancel()
        timerTask = nil
        guard drainTask == nil, !buffer.isEmpty else { return }
        drainTask = Task {
            await self.drainBufferedEntries()
            self.drainTask = nil
            // Entries staged in the window after the final empty check get a fresh timer.
            self.scheduleTimerIfNeeded()
        }
    }

    // MARK: - Delivery

    private func drainBufferedEntries() async {
        while true {
            let batch = buffer.removeBatch(upTo: maxBatchSize)
            guard !batch.isEmpty else { return }
            await send(batch)
        }
    }

    private func send(_ batch: [LogEntry]) async {
        let payload: Data
        do {
            payload = try payloadBuilder.payload(for: batch, credentials: credentials)
        } catch {
            internalLog.error("Failed to encode a batch — dropped \(batch.count) entries.")
            return
        }

        var attempt = 1
        while true {
            let outcome: SendOutcome
            do {
                let response = try await httpClient.post(
                    payload,
                    to: credentials.endpointURL,
                    headers: ["Content-Type": "application/json"]
                )
                outcome = retryPolicy.outcome(forStatusCode: response.statusCode)
            } catch {
                outcome = .retryable
            }

            switch outcome {
            case .success:
                internalLog.debug("Uploaded a batch of \(batch.count) entries.")
                return
            case .terminal:
                internalLog.error("Conductr rejected a batch — dropped \(batch.count) entries.")
                return
            case .retryable:
                guard attempt < retryPolicy.maxAttempts else {
                    internalLog.error(
                        "Delivery failed after \(attempt) attempts — dropped \(batch.count) entries."
                    )
                    return
                }
                let delay = retryPolicy.delay(afterAttempt: attempt)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                attempt += 1
            }
        }
    }
}
