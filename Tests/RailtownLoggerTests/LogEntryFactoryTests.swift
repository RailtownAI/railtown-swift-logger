//
//  LogEntryFactoryTests.swift
//  RailtownLoggerTests
//

import Foundation
import Testing
@testable import RailtownLogger

@Suite struct LogEntryFactoryTests {
    private let factory = LogEntryFactory(
        stackTraceProvider: FixedStackTraceProvider(lines: [
            "0   TestApp   0x0001 main + 10",
            "1   TestApp   0x0002 caller + 20",
        ]),
        contextProvider: FixedContextProvider(properties: [
            "OSVersion": "test-os"
        ]),
        dateProvider: FixedDateProvider(now: Date(timeIntervalSince1970: 42))
    )

    @Test func composesErrorTypeDescriptionAndStackTrace() {
        let entry = factory.entry(
            for: TestError.boom("kaput"),
            message: nil,
            level: .error,
            extraProperties: [:]
        )

        // The message is the error headline; the trace lives in the exception.
        #expect(entry.message.contains("TestError"))
        #expect(entry.message.contains(#"boom("kaput")"#))
        #expect(!entry.message.contains("main + 10"))
        let exception = try? #require(entry.exception)
        #expect(exception?.contains(#"boom("kaput")"#) == true)
        #expect(exception?.hasSuffix(
            "0   TestApp   0x0001 main + 10\n1   TestApp   0x0002 caller + 20"
        ) == true)
        #expect(entry.level == .error)
        #expect(entry.timestamp == Date(timeIntervalSince1970: 42))
        #expect(entry.properties["ErrorType"]?.contains("TestError") == true)
        #expect(entry.properties["ErrorDescription"] != nil)
        #expect(entry.properties["OSVersion"] == "test-os")
    }

    @Test func prefersAProvidedThrowSiteTrace() {
        let entry = factory.entry(
            for: TestError.boom("x"),
            message: nil,
            level: .error,
            extraProperties: [:],
            throwSiteTrace: ["throw-frame-0", "throw-frame-1"]
        )
        #expect(entry.exception?.hasSuffix("throw-frame-0\nthrow-frame-1") == true)
        #expect(entry.exception?.contains("main + 10") == false)
    }

    @Test func theCallerSuppliedMessageBecomesTheMessage() {
        let entry = factory.entry(
            for: TestError.boom("x"),
            message: "Checkout failed",
            level: .error,
            extraProperties: [:]
        )
        #expect(entry.message == "Checkout failed")
        #expect(entry.exception?.contains("TestError") == true)
    }

    @Test func plainMessagesCarryNoException() {
        let entry = factory.entry(message: "hello", level: .information, extraProperties: [:])
        #expect(entry.message == "hello")
        #expect(entry.exception == nil)
        #expect(entry.level == .information)
    }

    @Test func callerPropertiesWinOverProvidedContext() {
        let entry = factory.entry(
            message: "hello",
            level: .warning,
            extraProperties: ["OSVersion": "caller-override", "Custom": "value"]
        )
        #expect(entry.properties["OSVersion"] == "caller-override")
        #expect(entry.properties["Custom"] == "value")
    }

    @Test func truncatesOversizedInputs() {
        let entry = factory.entry(
            message: String(repeating: "x", count: 50_000),
            level: .information,
            extraProperties: ["Big": String(repeating: "y", count: 20_000)]
        )
        #expect(entry.message.count == 32_768)
        #expect(entry.properties["Big"]?.count == 8_192)
    }

    @Test func truncatesOversizedExceptions() {
        let entry = factory.entry(
            for: TestError.boom(String(repeating: "z", count: 50_000)),
            message: nil,
            level: .error,
            extraProperties: [:]
        )
        #expect(entry.exception?.count == 32_768)
    }
}
