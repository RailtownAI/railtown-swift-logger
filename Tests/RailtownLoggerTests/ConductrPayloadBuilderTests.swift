//
//  ConductrPayloadBuilderTests.swift
//  RailtownLoggerTests
//

import Foundation
import Testing
@testable import RailtownLogger

@Suite struct ConductrPayloadBuilderTests {
    private let builder = ConductrPayloadBuilder()

    @Test func buildsTheContractShape() throws {
        let entry = LogEntry(
            message: "Boom",
            level: .error,
            properties: ["Key": "Value"],
            timestamp: Date(timeIntervalSince1970: 0)
        )
        let data = try builder.payload(for: [entry], credentials: TestFixtures.makeCredentials())

        let envelopes = PayloadInspector.envelopes(in: data)
        #expect(envelopes.count == 1)
        let envelope = try #require(envelopes.first)

        let userProperties = try #require(envelope["UserProperties"] as? [String: String])
        #expect(userProperties == [
            "Encoding": "utf-8",
            "AuthenticationCode": "auth-code==",
            "ConnectionName": "example.railtownlogs.com",
            "ClientVersion": RailtownLoggerVersion.current,
        ])

        // Body must be a *string* containing JSON (nested encoding), not a JSON object.
        #expect(envelope["Body"] is String)
        let body = PayloadInspector.body(of: envelope)
        #expect(body.keys.sorted() == [
            "EnvironmentId", "Level", "Message", "OrganizationId",
            "ProjectId", "Properties", "Runtime", "TimeStamp",
        ])
        #expect(body["Message"] as? String == "Boom")
        #expect(body["Level"] as? Int == 4)
        #expect(body["Runtime"] as? String == "swift")
        #expect(body["Properties"] as? [String: String] == ["Key": "Value"])
        #expect(body["TimeStamp"] as? String == "1970-01-01T00:00:00.0000000+00:00")
        #expect(body["EnvironmentId"] as? String == "env-789")
        #expect(body["OrganizationId"] as? String == "org-123")
        #expect(body["ProjectId"] as? String == "proj-456")
    }

    @Test func errorEntriesCarryTheExceptionField() throws {
        let entry = LogEntry(
            message: "Checkout failed",
            level: .error,
            properties: [:],
            timestamp: Date(timeIntervalSince1970: 0),
            exception: "TestError: boom\nframe-0\nframe-1"
        )
        let data = try builder.payload(for: [entry], credentials: TestFixtures.makeCredentials())
        let body = try #require(
            PayloadInspector.envelopes(in: data).first.map(PayloadInspector.body(of:))
        )
        #expect(body["Exception"] as? String == "TestError: boom\nframe-0\nframe-1")
        #expect(body["Message"] as? String == "Checkout failed")
    }

    @Test func encodesOneEnvelopePerEntryInOrder() throws {
        let entries = ["first", "second", "third"].map { message in
            LogEntry(
                message: message,
                level: .warning,
                properties: [:],
                timestamp: Date(timeIntervalSince1970: 1)
            )
        }
        let data = try builder.payload(for: entries, credentials: TestFixtures.makeCredentials())
        #expect(PayloadInspector.messages(in: data) == ["first", "second", "third"])
    }

    @Test func survivesMessagesNeedingJSONEscaping() throws {
        let hostile = "Quotes \" backslash \\ newline \n unicode \u{1F6A8} tab \t"
        let entry = LogEntry(
            message: hostile,
            level: .error,
            properties: ["Path": "/a/b?c=d&e=f"],
            timestamp: Date(timeIntervalSince1970: 0)
        )
        let data = try builder.payload(for: [entry], credentials: TestFixtures.makeCredentials())
        let body = try #require(PayloadInspector.envelopes(in: data).first.map(PayloadInspector.body(of:)))
        #expect(body["Message"] as? String == hostile)
        #expect((body["Properties"] as? [String: String])?["Path"] == "/a/b?c=d&e=f")
    }
}
