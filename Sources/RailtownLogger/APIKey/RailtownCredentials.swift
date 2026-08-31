//
//  RailtownCredentials.swift
//  RailtownLogger
//

import Foundation

/// Connection identity decoded from a Railtown API key.
struct RailtownCredentials: Sendable, Equatable {
    /// Ingestion host, e.g. `xyz.railtownlogs.com`. Sent as `ConnectionName`.
    let host: String

    /// Sent as `OrganizationId` in each log body.
    let organizationID: String

    /// Sent as `ProjectId` in each log body.
    let projectID: String

    /// Sent as `AuthenticationCode` with each envelope.
    let authenticationCode: String

    /// Sent as `EnvironmentId` in each log body.
    let environmentID: String

    /// Upload endpoint derived from `host` (`https://<host>`, no path).
    let endpointURL: URL
}
