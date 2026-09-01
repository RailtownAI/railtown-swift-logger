//
//  RailtownLoggerError.swift
//  RailtownLogger
//

/// Errors thrown by the RailtownLogger SDK itself.
public enum RailtownLoggerError: Error, Equatable, Sendable {
    /// The API key could not be parsed. The reason describes the failure
    /// without echoing any key material.
    case invalidAPIKey(reason: String)

    /// The bundled `Railtown-Info.plist` is missing, unreadable, or has no usable
    /// `API_KEY` entry. The reason never echoes key material.
    case invalidConfigurationPlist(reason: String)

    /// An agent-run trace could not be read or encoded for upload. The reason
    /// describes the failure without echoing trace contents.
    case invalidTracePayload(reason: String)

    /// A trace upload was attempted before ``ConductrTraceUploader`` was configured.
    /// Only that type throws this: the ``RailtownLogger`` capture calls are no-ops
    /// until configured rather than failing.
    case notConfigured
}
