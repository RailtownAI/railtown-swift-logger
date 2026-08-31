//
//  ConductrTimestampFormatterTests.swift
//  RailtownLoggerTests
//

import Foundation
import Testing
@testable import RailtownLogger

@Suite struct ConductrTimestampFormatterTests {
    private let formatter = ConductrTimestampFormatter()

    @Test func formatsTheEpochInDotNetShape() {
        #expect(
            formatter.string(from: Date(timeIntervalSince1970: 0))
                == "1970-01-01T00:00:00.0000000+00:00"
        )
    }

    @Test func formatsFractionalSecondsInUTC() {
        // 2026-08-18T16:26:20.5Z; .5 is exactly representable, keeping the assertion stable.
        let date = Date(timeIntervalSince1970: 1_787_070_380.5)
        #expect(formatter.string(from: date) == "2026-08-18T16:26:20.5000000+00:00")
    }

    @Test func matchesTheContractShapeForArbitraryDates() throws {
        let string = formatter.string(from: Date(timeIntervalSince1970: 1_234_567_890.123))
        let regex = try NSRegularExpression(
            pattern: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}\+00:00$"#
        )
        let range = NSRange(string.startIndex..., in: string)
        #expect(regex.firstMatch(in: string, range: range) != nil, "Unexpected shape: \(string)")
    }
}
