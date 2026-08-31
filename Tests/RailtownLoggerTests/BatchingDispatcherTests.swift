//
//  BatchingDispatcherTests.swift
//  RailtownLoggerTests
//

import Foundation
import Testing
@testable import RailtownLogger

@Suite struct BatchingDispatcherTests {
    private func makeDispatcher(
        httpClient: MockHTTPClient,
        flushInterval: TimeInterval = 60,
        maxBatchSize: Int = 10,
        maxBufferedEntries: Int = 100,
        retryPolicy: RetryPolicy = RetryPolicy(maxAttempts: 3, baseDelay: 0.001, maxDelay: 0.01)
    ) throws -> BatchingDispatcher {
        BatchingDispatcher(
            credentials: try TestFixtures.makeCredentials(),
            flushInterval: flushInterval,
            maxBatchSize: maxBatchSize,
            maxBufferedEntries: maxBufferedEntries,
            retryPolicy: retryPolicy,
            payloadBuilder: ConductrPayloadBuilder(),
            httpClient: httpClient,
            internalLog: InternalLog(isEnabled: false)
        )
    }

    private func makeEntry(_ message: String = "event") -> LogEntry {
        LogEntry(
            message: message,
            level: .error,
            properties: [:],
            timestamp: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func holdsEntriesBelowBatchSizeUntilFlush() async throws {
        let httpClient = MockHTTPClient()
        let dispatcher = try makeDispatcher(httpClient: httpClient)

        dispatcher.stage(makeEntry("one"))
        dispatcher.stage(makeEntry("two"))
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(await httpClient.requestCount == 0)

        await dispatcher.flush()
        #expect(await httpClient.requestCount == 1)
        let request = try #require(await httpClient.requests.first)
        #expect(PayloadInspector.messages(in: request.body) == ["one", "two"])
    }

    @Test func uploadsAutomaticallyWhenTheBatchFills() async throws {
        let httpClient = MockHTTPClient()
        let dispatcher = try makeDispatcher(httpClient: httpClient, maxBatchSize: 3)

        for index in 1...3 {
            dispatcher.stage(makeEntry("message-\(index)"))
        }

        #expect(await eventually { await httpClient.requestCount >= 1 })
        await dispatcher.flush()
        #expect(await httpClient.requestCount == 1)
    }

    @Test func uploadsWhenTheFlushIntervalElapses() async throws {
        let httpClient = MockHTTPClient()
        let dispatcher = try makeDispatcher(httpClient: httpClient, flushInterval: 0.05)

        dispatcher.stage(makeEntry())

        #expect(await eventually { await httpClient.requestCount >= 1 })
    }

    @Test func retriesRetryableStatusesWithTheSamePayload() async throws {
        let httpClient = MockHTTPClient(script: [.status(500), .status(200)])
        let dispatcher = try makeDispatcher(httpClient: httpClient)

        dispatcher.stage(makeEntry())
        await dispatcher.flush()

        let requests = await httpClient.requests
        #expect(requests.count == 2)
        #expect(requests.first?.body == requests.last?.body)
    }

    @Test func retriesTransportErrors() async throws {
        let httpClient = MockHTTPClient(
            script: [.failure(URLError(.notConnectedToInternet)), .status(200)]
        )
        let dispatcher = try makeDispatcher(httpClient: httpClient)

        dispatcher.stage(makeEntry())
        await dispatcher.flush()

        #expect(await httpClient.requestCount == 2)
    }

    @Test func dropsTheBatchOnTerminalResponses() async throws {
        let httpClient = MockHTTPClient(script: [.status(400)])
        let dispatcher = try makeDispatcher(httpClient: httpClient)

        dispatcher.stage(makeEntry())
        await dispatcher.flush()
        #expect(await httpClient.requestCount == 1)

        // The rejected batch must not linger and resend.
        await dispatcher.flush()
        #expect(await httpClient.requestCount == 1)
    }

    @Test func dropsTheBatchWhenTheRetryBudgetIsExhausted() async throws {
        let httpClient = MockHTTPClient(fallback: .status(503))
        let dispatcher = try makeDispatcher(
            httpClient: httpClient,
            retryPolicy: RetryPolicy(maxAttempts: 2, baseDelay: 0.001, maxDelay: 0.01)
        )

        dispatcher.stage(makeEntry())
        await dispatcher.flush()
        #expect(await httpClient.requestCount == 2)

        await dispatcher.flush()
        #expect(await httpClient.requestCount == 2)
    }

    @Test func dropsTheOldestEntriesBeyondCapacity() async throws {
        let httpClient = MockHTTPClient()
        let dispatcher = try makeDispatcher(
            httpClient: httpClient,
            maxBatchSize: 50,
            maxBufferedEntries: 5
        )

        for index in 1...8 {
            dispatcher.stage(makeEntry("message-\(index)"))
        }
        await dispatcher.flush()

        let request = try #require(await httpClient.requests.first)
        #expect(PayloadInspector.messages(in: request.body) == [
            "message-4", "message-5", "message-6", "message-7", "message-8",
        ])
    }

    /// Before the clamp, arming the timer with an out-of-range interval overflowed the
    /// `UInt64` nanosecond conversion and trapped — crashing the test runner, not failing.
    @Test(arguments: [Double.infinity, .greatestFiniteMagnitude, .nan, -1])
    func clampsOutOfRangeFlushIntervalsInsteadOfTrapping(_ interval: TimeInterval) async throws {
        let httpClient = MockHTTPClient()
        let dispatcher = try makeDispatcher(httpClient: httpClient, flushInterval: interval)

        dispatcher.stage(makeEntry())
        await dispatcher.flush()

        #expect(await httpClient.requestCount == 1)
    }

    @Test func drainsInBatchSizedChunks() async throws {
        let httpClient = MockHTTPClient()
        let dispatcher = try makeDispatcher(httpClient: httpClient, maxBatchSize: 2)

        for index in 1...5 {
            dispatcher.stage(makeEntry("message-\(index)"))
        }
        await dispatcher.flush()

        let requests = await httpClient.requests
        let batchSizes = requests.map { PayloadInspector.messages(in: $0.body).count }
        #expect(batchSizes.reduce(0, +) == 5)
        #expect(batchSizes.allSatisfy { $0 <= 2 })
    }
}
