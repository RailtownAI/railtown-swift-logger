//
//  CallSiteTests.swift
//  RailtownLoggerTests
//

import Foundation
import Testing
@testable import RailtownLogger

@Suite struct CallSiteTests {
    private func makeClient(httpClient: MockHTTPClient) throws -> RailtownClient {
        RailtownClient(
            options: RailtownOptions(observesAppLifecycle: false),
            entryFactory: LogEntryFactory(
                stackTraceProvider: FixedStackTraceProvider(lines: ["0  TestApp  frame"]),
                contextProvider: FixedContextProvider(properties: ["OSVersion": "test"]),
                dateProvider: FixedDateProvider(now: Date(timeIntervalSince1970: 0))
            ),
            dispatcher: BatchingDispatcher(
                credentials: try TestFixtures.makeCredentials(),
                flushInterval: 60,
                maxBatchSize: 10,
                maxBufferedEntries: 100,
                retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0.001, maxDelay: 0.01),
                payloadBuilder: ConductrPayloadBuilder(),
                httpClient: httpClient,
                internalLog: InternalLog(isEnabled: false)
            ),
            internalLog: InternalLog(isEnabled: false)
        )
    }

    private func uploadedProperties(_ httpClient: MockHTTPClient) async throws -> [String: String] {
        let request = try #require(await httpClient.requests.first)
        let body = try #require(
            PayloadInspector.envelopes(in: request.body).first.map(PayloadInspector.body(of:))
        )
        return try #require(body["Properties"] as? [String: String])
    }

    @Test func captureRecordsTheCallSiteAutomatically() async throws {
        let httpClient = MockHTTPClient()
        let client = try makeClient(httpClient: httpClient)

        client.capture(TestError.boom("x"))   // <- the line under test
        await client.flush(timeout: 30)

        let properties = try await uploadedProperties(httpClient)
        #expect(properties["SourceFile"] == "RailtownLoggerTests/CallSiteTests.swift")
        #expect(properties["SourceFunction"] == "captureRecordsTheCallSiteAutomatically()")
        #expect(Int(properties["SourceLine"] ?? "") != nil)
    }

    @Test func logRecordsTheCallSiteToo() async throws {
        let httpClient = MockHTTPClient()
        let client = try makeClient(httpClient: httpClient)

        client.log("hello")
        await client.flush(timeout: 30)

        let properties = try await uploadedProperties(httpClient)
        #expect(properties["SourceFile"] == "RailtownLoggerTests/CallSiteTests.swift")
        #expect(properties["SourceFunction"] == "logRecordsTheCallSiteToo()")
    }

    /// The slots sit alongside the runtime context, in the same dictionary.
    @Test func callSiteSlotsLiveNextToTheRuntimeContext() async throws {
        let httpClient = MockHTTPClient()
        let client = try makeClient(httpClient: httpClient)

        client.capture(TestError.boom("x"))
        await client.flush(timeout: 30)

        let properties = try await uploadedProperties(httpClient)
        #expect(properties["OSVersion"] == "test")
        #expect(properties["SourceFile"] != nil)
    }

    @Test func fileIsAModuleRelativeIDNotAnAbsoluteBuildPath() async throws {
        let httpClient = MockHTTPClient()
        let client = try makeClient(httpClient: httpClient)

        client.capture(TestError.boom("x"))
        await client.flush(timeout: 30)

        let file = try #require(try await uploadedProperties(httpClient)["SourceFile"])
        #expect(!file.hasPrefix("/"))
        #expect(!file.contains("/Users/"))
    }

    @Test func callerSuppliedPropertiesWin() async throws {
        let httpClient = MockHTTPClient()
        let client = try makeClient(httpClient: httpClient)

        client.capture(TestError.boom("x"), properties: ["SourceFile": "override.swift"])
        await client.flush(timeout: 30)

        #expect(try await uploadedProperties(httpClient)["SourceFile"] == "override.swift")
    }

    /// A wrapper forwarding its own caller's position.
    @Test func anExplicitCallSiteCanBeForwarded() async throws {
        let httpClient = MockHTTPClient()
        let client = try makeClient(httpClient: httpClient)

        client.capture(TestError.boom("x"), file: "MyApp/Wrapper.swift", function: "doWork()", line: 42)
        await client.flush(timeout: 30)

        let properties = try await uploadedProperties(httpClient)
        #expect(properties["SourceFile"] == "MyApp/Wrapper.swift")
        #expect(properties["SourceFunction"] == "doWork()")
        #expect(properties["SourceLine"] == "42")
    }

    // MARK: - RailtracksSwift redirect

    /// RailtracksSwift knows where the error was *raised*; that is what should be
    /// recorded — not the reporting code inside RailtracksSwift.
    @Test func railtracksCaptureRecordsTheForwardedRaiseSite() async throws {
        let httpClient = MockHTTPClient()
        let client = try makeClient(httpClient: httpClient)

        client.captureRailtracks(
            TestError.boom("x"),
            flowTitle: "Flow",
            callSite: CallSite(file: "RailtracksSwift/RTSAgent.swift", function: "invoke()", line: 7)
        )
        await client.flush(timeout: 30)

        let properties = try await uploadedProperties(httpClient)
        #expect(properties["SourceFile"] == "RailtracksSwift/RTSAgent.swift")
        #expect(properties["SourceFunction"] == "invoke()")
        #expect(properties["SourceLine"] == "7")
        #expect(properties["FlowTitle"] == "Flow")
    }

    /// No default arguments on this path: an error without a recorded raise site
    /// must not be attributed to the SDK's own reporting code.
    @Test func railtracksCaptureWithoutAContextRecordsNoSourceSlots() async throws {
        let httpClient = MockHTTPClient()
        let client = try makeClient(httpClient: httpClient)

        client.captureRailtracks(TestError.boom("x"), flowTitle: "Flow")
        await client.flush(timeout: 30)

        let properties = try await uploadedProperties(httpClient)
        #expect(properties["SourceFile"] == nil)
        #expect(properties["SourceFunction"] == nil)
        #expect(properties["SourceLine"] == nil)
    }
}
