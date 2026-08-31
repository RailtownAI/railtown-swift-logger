//
//  FlushTimeoutTests.swift
//  RailtownLoggerTests
//

import Foundation
import Testing
@testable import RailtownLogger

@Suite struct FlushTimeoutTests {
    private func makeDispatcher(
        httpClient: any HTTPClient,
        maxBatchSize: Int = 10
    ) throws -> BatchingDispatcher {
        BatchingDispatcher(
            credentials: try TestFixtures.makeCredentials(),
            flushInterval: 60,
            maxBatchSize: maxBatchSize,
            maxBufferedEntries: 100,
            retryPolicy: RetryPolicy(maxAttempts: 3, baseDelay: 0.001, maxDelay: 0.01),
            payloadBuilder: ConductrPayloadBuilder(),
            httpClient: httpClient,
            internalLog: InternalLog(isEnabled: false)
        )
    }

    private func makeEntry(_ message: String = "event") -> LogEntry {
        LogEntry(message: message, level: .error, properties: [:], timestamp: Date(timeIntervalSince1970: 0))
    }

    @Test func flushReturnsWhenTheTimeoutElapses() async throws {
        let dispatcher = try makeDispatcher(httpClient: HangingHTTPClient())
        dispatcher.stage(makeEntry())

        let started = Date()
        await dispatcher.flush(timeout: 0.2)
        let elapsed = Date().timeIntervalSince(started)

        // Without the timeout this would block on the hanging request for a minute.
        #expect(elapsed < 5, "flush should return promptly, took \(elapsed)s")
    }

    @Test func aTimedOutFlushKeepsTheEntriesBuffered() async throws {
        let hanging = HangingHTTPClient()
        let dispatcher = try makeDispatcher(httpClient: hanging)
        dispatcher.stage(makeEntry("kept"))

        // The batch leaves the buffer to be sent; a cancelled send must put it
        // back, or a timed-out flush silently destroys entries.
        await dispatcher.flush(timeout: 0.2)
        await dispatcher.flush(timeout: 0.2)

        #expect(await hanging.requestCount == 2, "the requeued batch should be sent again")
    }

    @Test func flushSucceedsNormallyWellWithinTheTimeout() async throws {
        let httpClient = MockHTTPClient()
        let dispatcher = try makeDispatcher(httpClient: httpClient)
        dispatcher.stage(makeEntry())

        await dispatcher.flush(timeout: 30)

        #expect(await httpClient.requestCount == 1)
    }

    @Test func clientUsesTheConfiguredDefaultTimeout() async throws {
        let client = RailtownClient(
            options: RailtownOptions(flushTimeout: 0.2, observesAppLifecycle: false),
            entryFactory: LogEntryFactory(
                stackTraceProvider: FixedStackTraceProvider(lines: ["frame"]),
                contextProvider: FixedContextProvider(properties: [:]),
                dateProvider: FixedDateProvider(now: Date(timeIntervalSince1970: 0))
            ),
            dispatcher: try makeDispatcher(httpClient: HangingHTTPClient()),
            internalLog: InternalLog(isEnabled: false)
        )
        client.capture(TestError.boom("x"))

        let started = Date()
        await client.flush()          // no argument — the option supplies the bound
        #expect(Date().timeIntervalSince(started) < 5)
    }
}
