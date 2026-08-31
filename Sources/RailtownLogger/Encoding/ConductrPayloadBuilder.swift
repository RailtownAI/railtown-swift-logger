//
//  ConductrPayloadBuilder.swift
//  RailtownLogger
//

import Foundation

/// Builds the HTTP body for a batch of log entries.
protocol PayloadBuilding: Sendable {
    /// Renders `entries` as the JSON array Conductr ingests.
    func payload(for entries: [LogEntry], credentials: RailtownCredentials) throws -> Data
}

/// Two-pass encoder: each entry's body is JSON-encoded to a string first, then embedded
/// in its envelope, matching Conductr's nested `Body` contract. The outer encode
/// escapes the embedded JSON automatically.
struct ConductrPayloadBuilder: PayloadBuilding {
    private let timestampFormatter: any TimestampFormatting

    init(timestampFormatter: any TimestampFormatting = ConductrTimestampFormatter()) {
        self.timestampFormatter = timestampFormatter
    }

    func payload(for entries: [LogEntry], credentials: RailtownCredentials) throws -> Data {
        let encoder = JSONEncoder()
        // Sorted keys keep output deterministic (testable); slashes stay readable in URLs.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        let userProperties = ConductrUserProperties(
            encoding: ConductrWireFormat.encoding,
            authenticationCode: credentials.authenticationCode,
            connectionName: credentials.host,
            clientVersion: ConductrWireFormat.clientVersion
        )
        let envelopes: [ConductrLogEnvelope] = try entries.map { entry in
            let body = ConductrLogBody(
                message: entry.message,
                level: entry.level.rawValue,
                runtime: ConductrWireFormat.runtime,
                properties: entry.properties,
                timeStamp: timestampFormatter.string(from: entry.timestamp),
                environmentID: credentials.environmentID,
                organizationID: credentials.organizationID,
                projectID: credentials.projectID,
                exception: entry.exception
            )
            return ConductrLogEnvelope(
                body: String(decoding: try encoder.encode(body), as: UTF8.self),
                userProperties: userProperties
            )
        }
        return try encoder.encode(envelopes)
    }
}
