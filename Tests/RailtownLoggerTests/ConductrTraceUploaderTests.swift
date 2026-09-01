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

    @Test func configuresFromThePlist() throws {
        let bundle = try TestFixtures.makeBundle(
            plistContents: ["API_KEY": TestFixtures.makeKey(), "API_BASE_URL": TestFixtures.baseURL]
        )
        try uploader.configure(bundle: bundle)
        #expect(uploader.isConfigured)
        #expect(
            uploader.configuredExchangeURL
                == URL(string: "\(TestFixtures.baseURL)/observe/exchange")
        )
    }

    @Test func anExplicitBaseURLWinsOverThePlist() throws {
        let bundle = try TestFixtures.makeBundle(
            plistContents: ["API_KEY": TestFixtures.makeKey(), "API_BASE_URL": TestFixtures.baseURL]
        )
        try uploader.configure(apiBaseURL: "https://other.example.com/api", bundle: bundle)
        #expect(
            uploader.configuredExchangeURL
                == URL(string: "https://other.example.com/api/observe/exchange")
        )
    }

    @Test func configuresFromAPlistWithoutABaseURLWhenOneIsPassed() throws {
        let bundle = try TestFixtures.makeBundle(plistContents: ["API_KEY": TestFixtures.makeKey()])
        try uploader.configure(apiBaseURL: TestFixtures.baseURL, bundle: bundle)
        #expect(
            uploader.configuredExchangeURL
                == URL(string: "\(TestFixtures.baseURL)/observe/exchange")
        )
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
}
