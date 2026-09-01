//
//  APIKeyPlistLoader.swift
//  RailtownLogger
//

import Foundation

/// Reads Railtown configuration from a bundled `Railtown-Info.plist` — the Google-services
/// configuration style: ship the plist with the app, then call
/// ``RailtownLogger/configure(options:bundle:)`` with no key in source.
///
/// The same file serves both uploaders: ``RailtownLogger`` needs only `API_KEY`, while
/// ``ConductrTraceUploader`` also reads `API_BASE_URL` when its caller does not pass one.
struct APIKeyPlistLoader: Sendable {
    /// Bundled configuration file name, without extension.
    static let fileName = "Railtown-Info"

    /// Plist entry holding the base64 API key.
    static let apiKeyEntry = "API_KEY"

    /// Plist entry holding the Conductr host, e.g. `cndr.railtown.ai`. Optional: only
    /// ``ConductrTraceUploader`` reads it, and only when the caller passes no host.
    static let apiBaseURLEntry = "API_BASE_URL"

    /// - Throws: ``RailtownLoggerError/invalidConfigurationPlist(reason:)`` when the
    ///   file is absent, unreadable, or has no usable `API_KEY` entry.
    func apiKey(in bundle: Bundle) throws -> String {
        try string(forEntry: Self.apiKeyEntry, in: bundle)
    }

    /// - Throws: ``RailtownLoggerError/invalidConfigurationPlist(reason:)`` when the
    ///   file is absent, unreadable, or has no usable `API_BASE_URL` entry.
    func apiBaseURL(in bundle: Bundle) throws -> String {
        try string(forEntry: Self.apiBaseURLEntry, in: bundle)
    }

    /// Reads one non-empty string entry out of the bundled plist.
    private func string(forEntry entry: String, in bundle: Bundle) throws -> String {
        let contents = try contents(in: bundle)
        guard let value = contents[entry] as? String, !value.isEmpty else {
            throw RailtownLoggerError.invalidConfigurationPlist(
                reason: "\(Self.fileName).plist has no \(entry) string entry."
            )
        }
        return value
    }

    private func contents(in bundle: Bundle) throws -> [String: Any] {
        guard let url = bundle.url(forResource: Self.fileName, withExtension: "plist") else {
            throw RailtownLoggerError.invalidConfigurationPlist(
                reason: "\(Self.fileName).plist is not in the bundle."
            )
        }
        do {
            let data = try Data(contentsOf: url)
            return try PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any] ?? [:]
        } catch {
            throw RailtownLoggerError.invalidConfigurationPlist(
                reason: "\(Self.fileName).plist could not be read as a property list."
            )
        }
    }
}
