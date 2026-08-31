//
//  APIKeyParserTests.swift
//  RailtownLoggerTests
//

import Foundation
import Testing
@testable import RailtownLogger

@Suite struct APIKeyParserTests {
    private let parser = Base64APIKeyParser()

    /// Synthetic key — **not** a real credential, and deliberately not one.
    ///
    /// It decodes to `synthetic-fixture.example.invalid` with an authentication code that
    /// literally reads `NOT+A+REAL+KEY/...`, so anyone who base64-decodes it (the first thing
    /// a security audit does) can see that immediately rather than having to investigate.
    /// `.invalid` is reserved by RFC 2606 and can never resolve.
    ///
    /// It is shape-accurate in exactly the ways ``Base64APIKeyParser`` cares about, and no
    /// others. The parser exercises base64 decoding, JSON decoding of the `u`/`o`/`p`/`h`/`e`
    /// fields, the non-empty check on each, and the host round-trip through `URL(string:)` —
    /// it never validates UUID versions or the host's character set, so nothing is lost by
    /// making those obviously fake. The authentication code keeps `+`, `/`, and `=`, the
    /// characters most likely to break naive parsing.
    ///
    /// The encoded form carries one `=` of padding on purpose, so
    /// ``acceptsUnpaddedBase64`` exercises `Base64APIKeyParser.repadded`'s re-padding branch
    /// when it strips that padding off. Keep that property if you regenerate this.
    ///
    /// To confirm the parser against a genuinely platform-issued key, substitute one here
    /// locally and run the suite — but **do not commit it**. For an end-to-end check against
    /// the live endpoint, prefer the env-var path that leaves no key in source:
    /// `RAILTOWN_SMOKE_API_KEY="<key>" swift test --filter ConductrSmokeTests`
    private static let sampleKey =
        "eyJ1Ijoic3ludGhldGljLWZpeHR1cmUuZXhhbXBsZS5pbnZhbGlkIiwibyI6IjAwMDAwMDAwLTAwMDAtMDAwMC0wMDAwLTAwMDAwMDAwMDAwMCIsInAiOiIxMTExMTExMS0xMTExLTExMTEtMTExMS0xMTExMTExMTExMTEiLCJoIjoiTk9UK0ErUkVBTCtLRVkvc3ludGhldGljL3Rlc3QvZml4dHVyZS8wMDAwPT0iLCJlIjoiMjIyMjIyMjItMjIyMi0yMjIyLTIyMjItMjIyMjIyMjIyMjIyIn0="

    /// Every field lands on the credential property it belongs to — the mapping is the
    /// point here, since the single-letter JSON keys are easy to transpose.
    @Test func mapsEveryKeyFieldToItsCredential() throws {
        let credentials = try parser.parse(Self.sampleKey)
        #expect(credentials.host == "synthetic-fixture.example.invalid")
        #expect(credentials.organizationID == "00000000-0000-0000-0000-000000000000")
        #expect(credentials.projectID == "11111111-1111-1111-1111-111111111111")
        #expect(credentials.authenticationCode == "NOT+A+REAL+KEY/synthetic/test/fixture/0000==")
        #expect(credentials.environmentID == "22222222-2222-2222-2222-222222222222")
        #expect(
            credentials.endpointURL.absoluteString == "https://synthetic-fixture.example.invalid"
        )
    }

    @Test func acceptsUnpaddedBase64() throws {
        let unpadded = Self.sampleKey.trimmingCharacters(in: CharacterSet(charactersIn: "="))
        // Guard the guard: if the fixture ever stops needing re-padding, this test would
        // silently duplicate the one above instead of covering `repadded`.
        #expect(unpadded.count % 4 != 0, "Fixture must need re-padding for this test to mean anything")

        let credentials = try parser.parse(unpadded)
        #expect(credentials.host == "synthetic-fixture.example.invalid")
    }

    @Test func acceptsSurroundingWhitespace() throws {
        let credentials = try parser.parse("  \n\(TestFixtures.makeKey())\n\t")
        #expect(credentials.host == "example.railtownlogs.com")
    }

    @Test(arguments: [
        "",
        "   \n ",
        "not base64 at all!!!",
        Data("[1, 2, 3]".utf8).base64EncodedString(),
        Data(#"{"u":"example.com"}"#.utf8).base64EncodedString(),
        Data(#"{"u":"","o":"o","p":"p","h":"h","e":"e"}"#.utf8).base64EncodedString(),
        Data(#"{"u":"not a valid host","o":"o","p":"p","h":"h","e":"e"}"#.utf8)
            .base64EncodedString(),
    ])
    func rejectsMalformedKeys(_ rawKey: String) {
        #expect(throws: RailtownLoggerError.self) {
            try parser.parse(rawKey)
        }
    }

    @Test func rejectionReasonNeverEchoesKeyMaterial() {
        let secret = Data(#"{"u":"example.com"}"#.utf8).base64EncodedString()
        do {
            _ = try parser.parse(secret)
            Issue.record("Expected the parser to throw")
        } catch let RailtownLoggerError.invalidAPIKey(reason) {
            #expect(!reason.contains(secret))
            #expect(!reason.contains("example.com"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
