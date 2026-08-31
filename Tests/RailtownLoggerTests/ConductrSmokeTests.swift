//
//  ConductrSmokeTests.swift
//  RailtownLoggerTests
//

import Foundation
import Testing
@testable import RailtownLogger

/// Opt-in end-to-end check against the real Conductr ingestion endpoint: parses a real
/// key, builds a real payload, POSTs it, and asserts the server accepted it.
///
/// Skipped unless `RAILTOWN_SMOKE_API_KEY` holds an API key:
/// ```bash
/// RAILTOWN_SMOKE_API_KEY="<key>" swift test --filter ConductrSmokeTests
/// ```
@Suite struct ConductrSmokeTests {
    private static var smokeKey: String? {
        ProcessInfo.processInfo.environment["RAILTOWN_SMOKE_API_KEY"]
    }

    @Test(.enabled(if: smokeKey != nil))
    func endpointAcceptsARealUpload() async throws {
        let apiKey = try #require(Self.smokeKey)
        let credentials = try Base64APIKeyParser().parse(apiKey)

        let entry = LogEntry(
            message: "RailtownLogger smoke test — safe to ignore",
            level: .error,
            properties: [
                "Source": "ConductrSmokeTests"
            ],
            timestamp: Date()
        )
        let payload = try ConductrPayloadBuilder().payload(for: [entry], credentials: credentials)

        let response = try await URLSessionHTTPClient().post(
            payload,
            to: credentials.endpointURL,
            headers: ["Content-Type": "application/json"]
        )

        let responseBody = String(decoding: response.body, as: UTF8.self)
        print("Conductr responded \(response.statusCode): \(responseBody.prefix(500))")
        #expect(
            (200..<300).contains(response.statusCode),
            "Conductr rejected the upload — status \(response.statusCode), body: \(responseBody.prefix(500))"
        )
    }
}
