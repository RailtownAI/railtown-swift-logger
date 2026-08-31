//
//  RailtownLoggerFacadeTests.swift
//  RailtownLoggerTests
//

import Foundation
import Testing
@testable import RailtownLogger

/// Exercises the static facade. Serialized because the facade holds the one
/// shared client slot; every test resets it on entry and exit.
@Suite(.serialized) struct RailtownLoggerFacadeTests {
    private func makeMockedClient(
        options: RailtownOptions = RailtownOptions(),
        httpClient: MockHTTPClient
    ) throws -> RailtownClient {
        RailtownClient(
            options: options,
            entryFactory: LogEntryFactory(
                stackTraceProvider: FixedStackTraceProvider(lines: ["0  TestApp  frame"]),
                contextProvider: FixedContextProvider(properties: ["OSVersion": "test-os"]),
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

    @Test func unconfiguredCallsAreSafeNoOps() async {
        RailtownLogger.reset()
        defer { RailtownLogger.reset() }

        #expect(!RailtownLogger.isConfigured)
        RailtownLogger.capture(TestError.boom("ignored"))
        RailtownLogger.log("ignored")
        RailtownLogger.captureRailtracks(TestError.boom("ignored"), flowTitle: "Flow")
        await RailtownLogger.flush()
        #expect(!RailtownLogger.isConfigured)
    }

    @Test func configureRejectsMalformedKeysAndStaysUnconfigured() {
        RailtownLogger.reset()
        defer { RailtownLogger.reset() }

        #expect(throws: RailtownLoggerError.self) {
            try RailtownLogger.configure(apiKey: "definitely-not-a-key")
        }
        #expect(!RailtownLogger.isConfigured)
    }

    @Test func configureAcceptsAWellFormedKey() throws {
        RailtownLogger.reset()
        defer { RailtownLogger.reset() }

        try RailtownLogger.configure(apiKey: TestFixtures.makeKey())
        #expect(RailtownLogger.isConfigured)
    }

    @Test func configureReadsTheBundledPlist() throws {
        RailtownLogger.reset()
        defer { RailtownLogger.reset() }

        let bundle = try TestFixtures.makeBundle(plistContents: ["API_KEY": TestFixtures.makeKey()])
        try RailtownLogger.configure(bundle: bundle)
        #expect(RailtownLogger.isConfigured)
    }

    @Test func configureRejectsABundleWithoutThePlist() throws {
        RailtownLogger.reset()
        defer { RailtownLogger.reset() }

        let bundle = try TestFixtures.makeBundle(plistContents: nil)
        #expect(throws: RailtownLoggerError.self) {
            try RailtownLogger.configure(bundle: bundle)
        }
        #expect(!RailtownLogger.isConfigured)
    }

    @Test func captureFlowsThroughToTheTransport() async throws {
        RailtownLogger.reset()
        defer { RailtownLogger.reset() }

        let httpClient = MockHTTPClient()
        RailtownLogger.install(try makeMockedClient(httpClient: httpClient))

        RailtownLogger.capture(TestError.boom("kaput"), properties: ["Screen": "Checkout"])
        await RailtownLogger.flush()

        let request = try #require(await httpClient.requests.first)
        #expect(request.url.absoluteString == "https://example.railtownlogs.com")
        #expect(request.headers["Content-Type"] == "application/json")

        let body = try #require(
            PayloadInspector.envelopes(in: request.body).first.map(PayloadInspector.body(of:))
        )
        #expect(body["Level"] as? Int == 4)
        let message = try #require(body["Message"] as? String)
        #expect(message.contains("kaput"))
        let exception = try #require(body["Exception"] as? String)
        #expect(exception.contains("0  TestApp  frame"))
        let properties = try #require(body["Properties"] as? [String: String])
        #expect(properties["Screen"] == "Checkout")
    }

    @Test func logMessagesQuoteInterpolatedValues() async throws {
        RailtownLogger.reset()
        defer { RailtownLogger.reset() }

        let httpClient = MockHTTPClient()
        RailtownLogger.install(try makeMockedClient(httpClient: httpClient))

        let screen = "Checkout"
        RailtownLogger.log("Opened \(screen) with \(3) items")
        await RailtownLogger.flush()

        let request = try #require(await httpClient.requests.first)
        let body = try #require(
            PayloadInspector.envelopes(in: request.body).first.map(PayloadInspector.body(of:))
        )
        #expect(body["Message"] as? String == "Opened 'Checkout' with 3 items")
    }

    @Test func railtracksCaptureUploadsWhenEnabled() async throws {
        RailtownLogger.reset()
        defer { RailtownLogger.reset() }

        let httpClient = MockHTTPClient()
        RailtownLogger.install(try makeMockedClient(httpClient: httpClient))

        RailtownLogger.captureRailtracks(
            TestError.boom("flow blew up"),
            flowTitle: "Math Flow",
            properties: ["RailtracksVersion": "9.9.9"]
        )
        await RailtownLogger.flush()

        let request = try #require(await httpClient.requests.first)
        let body = try #require(
            PayloadInspector.envelopes(in: request.body).first.map(PayloadInspector.body(of:))
        )
        let message = try #require(body["Message"] as? String)
        #expect(message.contains("RailtracksSwift flow 'Math Flow' failed"))
        let properties = try #require(body["Properties"] as? [String: String])
        #expect(properties["FlowTitle"] == "Math Flow")
        #expect(properties["Source"] == "RailtracksSwift")
        #expect(properties["RailtracksVersion"] == "9.9.9")
    }

    @Test func railtracksCaptureHonorsTheOptOut() async throws {
        RailtownLogger.reset()
        defer { RailtownLogger.reset() }

        let httpClient = MockHTTPClient()
        RailtownLogger.install(
            try makeMockedClient(
                options: RailtownOptions(capturesRailtracksErrors: false),
                httpClient: httpClient
            )
        )

        RailtownLogger.captureRailtracks(TestError.boom("ignored"), flowTitle: "Flow")
        await RailtownLogger.flush()

        #expect(await httpClient.requestCount == 0)
    }

    @Test func railtracksCaptureUploadsAProvidedThrowSiteTrace() async throws {
        RailtownLogger.reset()
        defer { RailtownLogger.reset() }

        let httpClient = MockHTTPClient()
        RailtownLogger.install(try makeMockedClient(httpClient: httpClient))

        RailtownLogger.captureRailtracks(
            TestError.boom("kaput"),
            flowTitle: "Flow",
            stackTrace: ["deep-throw-frame-0", "deep-throw-frame-1"]
        )
        await RailtownLogger.flush()

        let request = try #require(await httpClient.requests.first)
        let body = try #require(
            PayloadInspector.envelopes(in: request.body).first.map(PayloadInspector.body(of:))
        )
        let exception = try #require(body["Exception"] as? String)
        #expect(exception.contains("deep-throw-frame-0\ndeep-throw-frame-1"))
    }

    @Test func entryMirrorWritesAFilePerCapture() async throws {
        RailtownLogger.reset()
        defer { RailtownLogger.reset() }

        let mirrorDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("railtown-mirror-\(UUID().uuidString)", isDirectory: true)
        RailtownLogger.install(
            try makeMockedClient(
                options: RailtownOptions(entryMirrorDirectory: mirrorDirectory),
                httpClient: MockHTTPClient()
            )
        )

        RailtownLogger.capture(TestError.boom("mirrored"))

        let mirrored = await eventually {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: mirrorDirectory.path)) ?? []
            return !files.isEmpty
        }
        #expect(mirrored)
        let files = try FileManager.default.contentsOfDirectory(atPath: mirrorDirectory.path)
        let contents = try String(
            contentsOf: mirrorDirectory.appendingPathComponent(try #require(files.first)),
            encoding: .utf8
        )
        #expect(contents.contains("mirrored"))
        #expect(contents.contains("Exception:"))
    }

    @Test func reconfigureReplacesTheClient() async throws {
        RailtownLogger.reset()
        defer { RailtownLogger.reset() }

        let firstHTTPClient = MockHTTPClient()
        let secondHTTPClient = MockHTTPClient()
        RailtownLogger.install(try makeMockedClient(httpClient: firstHTTPClient))
        RailtownLogger.install(try makeMockedClient(httpClient: secondHTTPClient))

        RailtownLogger.capture(TestError.boom("after swap"))
        await RailtownLogger.flush()

        #expect(await firstHTTPClient.requestCount == 0)
        #expect(await secondHTTPClient.requestCount == 1)
    }
}
