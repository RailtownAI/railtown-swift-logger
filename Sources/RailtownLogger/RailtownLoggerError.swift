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
}
