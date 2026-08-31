//
//  ConductrModels.swift
//  RailtownLogger
//

import Foundation

/// Wire-format constants shared by every upload.
enum ConductrWireFormat {
    /// Runtime identifier Conductr files this SDK's events under.
    static let runtime = "swift"

    static let encoding = "utf-8"

    /// The SDK's own version, sent as `ClientVersion`.
    static var clientVersion: String { RailtownLoggerVersion.current }
}

/// Inner payload serialized into the envelope's `Body` string.
struct ConductrLogBody: Encodable {
    let message: String
    let level: Int
    let runtime: String
    let properties: [String: String]
    let timeStamp: String
    let environmentID: String
    let organizationID: String
    let projectID: String

    /// Error details — type, description, and stack trace. Absent for plain messages.
    let exception: String?

    enum CodingKeys: String, CodingKey {
        case message = "Message"
        case level = "Level"
        case runtime = "Runtime"
        case properties = "Properties"
        case timeStamp = "TimeStamp"
        case environmentID = "EnvironmentId"
        case organizationID = "OrganizationId"
        case projectID = "ProjectId"
        case exception = "Exception"
    }
}

/// Delivery metadata attached to each envelope.
struct ConductrUserProperties: Encodable {
    let encoding: String
    let authenticationCode: String
    let connectionName: String
    let clientVersion: String

    enum CodingKeys: String, CodingKey {
        case encoding = "Encoding"
        case authenticationCode = "AuthenticationCode"
        case connectionName = "ConnectionName"
        case clientVersion = "ClientVersion"
    }
}

/// One element of the JSON array POSTed to Conductr. `body` carries the
/// JSON-encoded ``ConductrLogBody`` as a string — nested encoding, per the contract.
struct ConductrLogEnvelope: Encodable {
    let body: String
    let userProperties: ConductrUserProperties

    enum CodingKeys: String, CodingKey {
        case body = "Body"
        case userProperties = "UserProperties"
    }
}
