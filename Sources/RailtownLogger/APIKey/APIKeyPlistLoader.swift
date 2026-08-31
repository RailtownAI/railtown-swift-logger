//
//  APIKeyPlistLoader.swift
//  RailtownLogger
//

import Foundation

/// Reads the API key from a bundled `Railtown-Info.plist` — the Google-services
/// configuration style: ship the plist with the app, then call
/// ``RailtownLogger/configure(options:bundle:)`` with no key in source.
struct APIKeyPlistLoader: Sendable {
    /// Bundled configuration file name, without extension.
    static let fileName = "Railtown-Info"

    /// Plist entry holding the base64 API key.
    static let apiKeyEntry = "API_KEY"

    /// - Throws: ``RailtownLoggerError/invalidConfigurationPlist(reason:)`` when the
    ///   file is absent, unreadable, or has no usable `API_KEY` entry.
    func apiKey(in bundle: Bundle) throws -> String {
        guard let url = bundle.url(forResource: Self.fileName, withExtension: "plist") else {
            throw RailtownLoggerError.invalidConfigurationPlist(
                reason: "\(Self.fileName).plist is not in the bundle."
            )
        }
        let contents: [String: Any]
        do {
            let data = try Data(contentsOf: url)
            contents = try PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any] ?? [:]
        } catch {
            throw RailtownLoggerError.invalidConfigurationPlist(
                reason: "\(Self.fileName).plist could not be read as a property list."
            )
        }
        guard let apiKey = contents[Self.apiKeyEntry] as? String, !apiKey.isEmpty else {
            throw RailtownLoggerError.invalidConfigurationPlist(
                reason: "\(Self.fileName).plist has no \(Self.apiKeyEntry) string entry."
            )
        }
        return apiKey
    }
}
