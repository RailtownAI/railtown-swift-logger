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

    // MARK: - ErrorType

    @Test func qualifiesAnEnumCaseCarryingAssociatedValues() {
        #expect(errorType(of: TestError.boom("x")) == "RailtownLoggerTests.TestError.boom")
    }

    @Test func qualifiesAPayloadFreeEnumCase() {
        #expect(
            errorType(of: PayloadFreeError.somethingFailed)
                == "RailtownLoggerTests.PayloadFreeError.somethingFailed"
        )
    }

    /// `String(reflecting:)` hands back the custom text instead of `Type.case`, putting the case
    /// name out of reach — so the bare type name is all that can be reported.
    @Test func fallsBackToTheTypeNameForAnEnumWithACustomDescription() {
        #expect(errorType(of: DescribedError.somethingFailed) == "RailtownLoggerTests.DescribedError")
    }

    /// Regression guard: a mirror's first child is a case name only for an enum. Without the
    /// `displayStyle` check these reported the first *stored property* — `HTTPError.statusCode` —
    /// an identifier that names no failure and shifts whenever the fields are reordered.
    @Test func reportsTheBareTypeNameForAStructError() {
        #expect(
            errorType(of: HTTPError(statusCode: 500, body: "boom"))
                == "RailtownLoggerTests.HTTPError"
        )
        #expect(
            errorType(of: HTTPError(body: "boom", statusCode: 500))
                == "RailtownLoggerTests.HTTPError",
            "Field order must not change the grouping key."
        )
    }

    @Test func reportsTheBareTypeNameForAClassError() {
        #expect(errorType(of: ClassError()) == "RailtownLoggerTests.ClassError")
    }

    @Test func reportsTheBareTypeNameForABridgedNSError() {
        #expect(errorType(of: NSError(domain: "TestDomain", code: 7)) == "NSError")
    }

    // MARK: - ErrorType stability for non-internal types
    //
    // `String(reflecting:)` renders these with a mangled context holding a pointer that is
    // reassigned every launch — `RailtownLoggerTests.(unknown context at $10f2c9b4).Foo`. Left in,
    // it makes ErrorType a fresh value per app run, fragmenting one error across every launch.
    // The literals below therefore also assert that no `$` address survives.

    @Test func stripsTheMangledContextFromAPrivateType() {
        #expect(
            errorType(of: PrivateFixtureError.somethingFailed)
                == "RailtownLoggerTests.PrivateFixtureError.somethingFailed"
        )
    }

    @Test func stripsTheMangledContextFromAFilePrivateTypeCarryingAPayload() {
        #expect(
            errorType(of: FilePrivateFixtureError.somethingFailed(code: 3))
                == "RailtownLoggerTests.FilePrivateFixtureError.somethingFailed"
        )
    }

    /// A type declared inside a function carries *two* context segments, so a fix that stripped
    /// only one would leave an address behind.
    @Test func stripsEveryMangledContextFromAFunctionLocalType() {
        #expect(
            errorType(of: makeFunctionLocalError())
                == "RailtownLoggerTests.FunctionLocalError.somethingFailed"
        )
    }

    /// The strip splits on `.` and rejoins, so a generic parameter's own dots must survive.
    @Test func leavesAGenericTypeNameIntact() {
        #expect(
            errorType(of: GenericFixtureError(value: 1))
                == "RailtownLoggerTests.GenericFixtureError<Swift.Int>"
        )
    }

    private func errorType(of error: any Error) -> String? {
        factory.entry(for: error, message: nil, level: .error, extraProperties: [:])
            .properties["ErrorType"]
    }
}

// MARK: - ErrorType fixtures

enum PayloadFreeError: Error {
    case somethingFailed
}

enum DescribedError: Error, CustomStringConvertible {
    case somethingFailed

    var description: String { "a hand-written description" }
}

/// Two stored properties, so a mirror-child lookup would pick one of them arbitrarily.
struct HTTPError: Error {
    let statusCode: Int
    let body: String

    init(statusCode: Int, body: String) {
        self.statusCode = statusCode
        self.body = body
    }

    /// Same fields, declared in the other order at the call site.
    init(body: String, statusCode: Int) {
        self.statusCode = statusCode
        self.body = body
    }
}

final class ClassError: Error {
    let code = 3
}

/// Deliberately `private`/`fileprivate`: these render with a mangled context, which is the whole
/// point of the stability tests above. Every other fixture here is internal so its name is stable.
private enum PrivateFixtureError: Error {
    case somethingFailed
}

fileprivate enum FilePrivateFixtureError: Error {
    case somethingFailed(code: Int)
}

struct GenericFixtureError<Value: Sendable>: Error {
    let value: Value
}

/// A function-scope type: rendered with *two* mangled context segments, unlike one declared
/// inside a suite's method, which Swift qualifies with the suite name instead.
func makeFunctionLocalError() -> any Error {
    enum FunctionLocalError: Error {
        case somethingFailed
    }
    return FunctionLocalError.somethingFailed
}
