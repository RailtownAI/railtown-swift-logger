//
//  ConductrTraceUploaderTests.swift
//  RailtownLoggerTests
//

import Foundation
import Testing
@testable import RailtownLogger

/// Serialized: every case configures the process-wide ``ConductrTraceUploader/shared``, so parallel
/// cases would overwrite each other's configuration between the call and the assertion.
@Suite(.serialized) struct ConductrTraceUploaderConfigurationTests {
    private let uploader = ConductrTraceUploader.shared

    // MARK: - Plist resolution

    @Test func configuresFromThePlist() throws {
        let bundle = try TestFixtures.makeBundle(
            plistContents: ["API_KEY": TestFixtures.makeKey(), "API_BASE_URL": TestFixtures.baseURL]
        )
        try uploader.configure(bundle: bundle)
        #expect(uploader.isConfigured)
        #expect(uploader.configuredExchangeURL == TestFixtures.exchangeURL)
    }

    @Test func anExplicitBaseURLWinsOverThePlist() throws {
        let bundle = try TestFixtures.makeBundle(
            plistContents: ["API_KEY": TestFixtures.makeKey(), "API_BASE_URL": TestFixtures.baseURL]
        )
        try uploader.configure(apiBaseURL: "other.example.com", bundle: bundle)
        #expect(
            uploader.configuredExchangeURL
                == URL(string: "https://other.example.com/api/observe/exchange")
        )
    }

    @Test func configuresFromAPlistWithoutABaseURLWhenOneIsPassed() throws {
        let bundle = try TestFixtures.makeBundle(plistContents: ["API_KEY": TestFixtures.makeKey()])
        try uploader.configure(apiBaseURL: TestFixtures.baseURL, bundle: bundle)
        #expect(uploader.configuredExchangeURL == TestFixtures.exchangeURL)
    }

    @Test func rejectsAPlistWithoutABaseURLWhenNoneIsPassed() throws {
        let bundle = try TestFixtures.makeBundle(plistContents: ["API_KEY": TestFixtures.makeKey()])
        #expect(throws: RailtownLoggerError.self) {
            try uploader.configure(bundle: bundle)
        }
    }

    @Test func rejectsABundleWithoutThePlist() throws {
        let bundle = try TestFixtures.makeBundle(plistContents: nil)
        #expect(throws: RailtownLoggerError.self) {
            try uploader.configure(apiBaseURL: TestFixtures.baseURL, bundle: bundle)
        }
    }

    @Test func rejectsAMalformedKeyInThePlist() throws {
        let bundle = try TestFixtures.makeBundle(
            plistContents: ["API_KEY": "not-a-key", "API_BASE_URL": TestFixtures.baseURL]
        )
        #expect(throws: RailtownLoggerError.self) {
            try uploader.configure(bundle: bundle)
        }
    }

    // MARK: - Host resolution

    /// Every spelling of the same host an integrator might type into the plist.
    @Test(arguments: [
        "https://conductr.example.com",
        "conductr.example.com",
        "https://conductr.example.com/",
        "conductr.example.com/",
        "  https://conductr.example.com  ",
    ])
    func resolvesTheExchangeURLFromAHost(_ apiBaseURL: String) throws {
        try uploader.configure(apiKey: TestFixtures.makeKey(), apiBaseURL: apiBaseURL)
        #expect(uploader.configuredExchangeURL == TestFixtures.exchangeURL)
    }

    @Test func keepsAnExplicitNonDefaultScheme() throws {
        try uploader.configure(apiKey: TestFixtures.makeKey(), apiBaseURL: "http://localhost:8080")
        #expect(
            uploader.configuredExchangeURL
                == URL(string: "http://localhost:8080/api/observe/exchange")
        )
    }

    @Test(arguments: ["", "   ", "https://", "conductr example.com"])
    func rejectsAnUnusableHost(_ apiBaseURL: String) throws {
        #expect(throws: URLError.self) {
            try uploader.configure(apiKey: TestFixtures.makeKey(), apiBaseURL: apiBaseURL)
        }
    }

    // MARK: - Upload preconditions

    /// A JSON array parses fine but is not the object shape a trace file must have. Rejected before
    /// any network call, so this never leaves the process.
    @Test func rejectsATraceFileThatIsNotAJSONObject() async throws {
        try uploader.configure(apiKey: TestFixtures.makeKey(), apiBaseURL: TestFixtures.baseURL)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trace-\(UUID().uuidString).json")
        try Data(#"["not", "an", "object"]"#.utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        await #expect(throws: RailtownLoggerError.invalidTracePayload(
            reason: "The trace file does not hold a JSON object."
        )) {
            try await uploader.uploadAgentRun(fileURL: fileURL)
        }
    }
}
