//
//  RailtownMessageTests.swift
//  RailtownLoggerTests
//

import Foundation
import Testing
@testable import RailtownLogger

@Suite struct RailtownMessageTests {
    @Test func literalsPassThroughUnchanged() {
        let message: RailtownMessage = "plain message, no interpolation"
        #expect(message.rendered == "plain message, no interpolation")
    }

    @Test func interpolatedValuesAreSingleQuoted() {
        let source = "LogsWindow"
        let thread = "background"
        let message: RailtownMessage = "Manager capture from \(source) on the \(thread) thread"
        #expect(message.rendered == "Manager capture from 'LogsWindow' on the 'background' thread")
    }

    @Test func numbersStayBare() {
        let count = 3
        let ratio = 0.5
        let message: RailtownMessage = "Uploaded \(count) items (\(ratio) of total)"
        #expect(message.rendered == "Uploaded 3 items (0.5 of total)")
    }

    @Test func rawOptsOutOfQuoting() {
        let prebuilt = "already formatted"
        let message: RailtownMessage = "Prefix: \(raw: prebuilt)"
        #expect(message.rendered == "Prefix: already formatted")
    }

    @Test func nonStringValuesAreQuotedViaTheirDescription() throws {
        let id = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let message: RailtownMessage = "Board \(id) saved"
        #expect(message.rendered == "Board 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE' saved")
    }

    @Test func optionalsRenderTheirWrappedValue() {
        let name: String? = "Bob"
        let message: RailtownMessage = "User \(name) signed in"
        #expect(message.rendered == "User 'Bob' signed in")
    }

    @Test func emptyOptionalsRenderAsNil() {
        let name: String? = nil
        let message: RailtownMessage = "User \(name) signed in"
        #expect(message.rendered == "User nil signed in")
    }

    @Test func optionalNumbersStayBare() {
        let count: Int? = 3
        let missing: Int? = nil
        let message: RailtownMessage = "Uploaded \(count) of \(missing)"
        #expect(message.rendered == "Uploaded 3 of nil")
    }

    @Test func rawUnwrapsOptionals() {
        let prebuilt: String? = "already formatted"
        let absent: String? = nil
        let message: RailtownMessage = "Prefix: \(raw: prebuilt), absent: \(raw: absent)"
        #expect(message.rendered == "Prefix: already formatted, absent: nil")
    }
}
