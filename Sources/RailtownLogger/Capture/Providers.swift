//
//  Providers.swift
//  RailtownLogger
//

import Foundation

/// Supplies the current call stack as readable text lines.
protocol StackTraceProviding: Sendable {
    /// Must run on the capturing thread — call it before hopping executors.
    func currentStackTrace() -> [String]
}

/// Uses `Thread.callStackSymbols`: one line per frame with index, module, address,
/// and (where symbols are available) the mangled symbol name.
struct ThreadStackTraceProvider: StackTraceProviding {
    func currentStackTrace() -> [String] {
        Thread.callStackSymbols
    }
}

/// Supplies ambient facts attached to every log entry.
protocol RuntimeContextProviding: Sendable {
    func contextProperties() -> [String: String]
}

/// Reads app identity from the main bundle and OS details from `ProcessInfo`.
struct RuntimeContextProvider: RuntimeContextProviding {
    func contextProperties() -> [String: String] {
        // The SDK version is not included here — it already travels as the
        // envelope's ClientVersion.
        var properties = [
            "OSVersion": ProcessInfo.processInfo.operatingSystemVersionString
        ]
        let bundle = Bundle.main
        if let bundleID = bundle.bundleIdentifier {
            properties["AppBundleId"] = bundleID
        }
        if let appVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String {
            properties["AppVersion"] = appVersion
        }
        if let buildNumber = bundle.infoDictionary?["CFBundleVersion"] as? String {
            properties["AppBuild"] = buildNumber
        }
        return properties
    }
}

/// Supplies the current time; injectable so tests get deterministic timestamps.
protocol DateProviding: Sendable {
    var now: Date { get }
}

struct SystemDateProvider: DateProviding {
    var now: Date { Date() }
}
