//
//  APIKeyParser.swift
//  RailtownLogger
//

import Foundation

/// Parses the API key issued by the Railtown platform into connection credentials.
protocol APIKeyParsing: Sendable {
    /// Decodes `rawKey` into credentials.
    /// - Throws: ``RailtownLoggerError/invalidAPIKey(reason:)`` when the key is malformed.
    func parse(_ rawKey: String) throws -> RailtownCredentials
}

/// Default parser. The key is base64 (possibly unpadded) of a JSON object:
/// `{"u": host, "o": organizationID, "p": projectID, "h": authenticationCode, "e": environmentID}`.
struct Base64APIKeyParser: APIKeyParsing {
    func parse(_ rawKey: String) throws -> RailtownCredentials {
        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RailtownLoggerError.invalidAPIKey(reason: "The key is empty.")
        }
        guard let data = Data(base64Encoded: Self.repadded(trimmed)) else {
            throw RailtownLoggerError.invalidAPIKey(reason: "The key is not valid base64.")
        }
        let payload: KeyPayload
        do {
            payload = try JSONDecoder().decode(KeyPayload.self, from: data)
        } catch {
            throw RailtownLoggerError.invalidAPIKey(
                reason: "The key does not decode to the expected JSON shape."
            )
        }
        for (field, value) in [
            ("host", payload.host),
            ("organization", payload.organizationID),
            ("project", payload.projectID),
            ("authentication code", payload.authenticationCode),
            ("environment", payload.environmentID),
        ] where value.isEmpty {
            throw RailtownLoggerError.invalidAPIKey(reason: "The key's \(field) field is empty.")
        }
        guard
            let endpointURL = URL(string: "https://\(payload.host)"),
            endpointURL.host == payload.host
        else {
            throw RailtownLoggerError.invalidAPIKey(reason: "The key's host is not a valid host name.")
        }
        return RailtownCredentials(
            host: payload.host,
            organizationID: payload.organizationID,
            projectID: payload.projectID,
            authenticationCode: payload.authenticationCode,
            environmentID: payload.environmentID,
            endpointURL: endpointURL
        )
    }

    /// Keys are often copied without base64 padding; restore it so `Data(base64Encoded:)` accepts them.
    private static func repadded(_ base64: String) -> String {
        let remainder = base64.count % 4
        guard remainder > 0 else { return base64 }
        return base64 + String(repeating: "=", count: 4 - remainder)
    }

    private struct KeyPayload: Decodable {
        let host: String
        let organizationID: String
        let projectID: String
        let authenticationCode: String
        let environmentID: String

        enum CodingKeys: String, CodingKey {
            case host = "u"
            case organizationID = "o"
            case projectID = "p"
            case authenticationCode = "h"
            case environmentID = "e"
        }
    }
}
