//
//  RailtownLogger.swift
//  RailtownLogger
//

import Foundation

/// Static entry point for Railtown/Conductr error reporting.
///
/// Configure once before the app launches, then capture from anywhere:
/// ```swift
/// try RailtownLogger.configure(apiKey: "<key from the Railtown platform>")
/// RailtownLogger.capture(error)
/// ```
///
/// The facade delegates to a single shared ``RailtownClient``. Apps that prefer
/// dependency injection can instantiate ``RailtownClient`` directly instead —
/// all behavior lives there; this type only holds the shared slot.
public enum RailtownLogger {
    private static let store = SharedClientStore()

    /// Parses the API key and activates the shared client.
    ///
    /// Call it again to reconfigure: the new client replaces the previous one,
    /// whose buffered entries are flushed in the background.
    ///
    /// - Parameters:
    ///   - apiKey: The base64 key issued by the platform.
    ///   - options: Behavior switches; defaults are production-appropriate.
    /// - Throws: ``RailtownLoggerError/invalidAPIKey(reason:)`` when the key cannot be parsed.
    public static func configure(apiKey: String, options: RailtownOptions = RailtownOptions()) throws {
        install(try RailtownClient(apiKey: apiKey, options: options))
    }

    /// Reads the API key from the app's bundled `Railtown-Info.plist` and activates
    /// the shared client — the Google-services configuration style: ship a plist with
    /// a single `API_KEY` string entry, then call `try RailtownLogger.configure()`
    /// with no key in source.
    ///
    /// - Parameters:
    ///   - options: Behavior switches; defaults are production-appropriate.
    ///   - bundle: Where to look for `Railtown-Info.plist`; defaults to the main bundle.
    /// - Throws: ``RailtownLoggerError`` when the plist is missing or its key cannot be parsed.
    public static func configure(
        options: RailtownOptions = RailtownOptions(),
        bundle: Bundle = .main
    ) throws {
        install(try RailtownClient(options: options, bundle: bundle))
    }

    /// Whether ``configure(apiKey:options:)`` has succeeded.
    public static var isConfigured: Bool {
        store.client != nil
    }

    /// Reports an error at ``RailtownLogLevel/error`` level. The error's type,
    /// description, and this call site's stack trace upload as the event's
    /// exception. No-op until configured.
    ///
    /// - Parameters:
    ///   - error: The error to report.
    ///   - message: Optional event message; defaults to the error's description.
    ///   - properties: Extra key–value context; wins over SDK-provided keys on conflict.
    public static func capture(
        _ error: any Error,
        message: RailtownMessage? = nil,
        properties: [String: String] = [:]
    ) {
        store.client?.capture(error, message: message, properties: properties)
    }

    /// Sends a plain message at the given level. No-op until configured.
    ///
    /// - Parameters:
    ///   - message: The message text.
    ///   - level: Severity; defaults to ``RailtownLogLevel/information``.
    ///   - properties: Extra key–value context; wins over SDK-provided keys on conflict.
    public static func log(
        _ message: RailtownMessage,
        level: RailtownLogLevel = .information,
        properties: [String: String] = [:]
    ) {
        store.client?.log(message, level: level, properties: properties)
    }

    /// Uploads everything buffered, waiting for delivery — including retries — to
    /// finish. Call from `scenePhase == .background` (or equivalent) to minimize
    /// loss when the app is suspended. No-op until configured.
    public static func flush() async {
        await store.client?.flush()
    }

    /// Automatic capture channel used by RailtracksSwift. No-op unless the app has
    /// configured the logger and left ``RailtownOptions/capturesRailtracksErrors`` enabled.
    ///
    /// - Parameters:
    ///   - error: The error that escaped the flow.
    ///   - flowTitle: Display name of the failed flow.
    ///   - properties: Extra key–value context supplied by RailtracksSwift.
    ///   - stackTrace: Optional stack trace RailtracksSwift captured at the throw
    ///     site; when present it replaces the capture-site trace.
    public static func captureRailtracks(
        _ error: any Error,
        flowTitle: String,
        properties: [String: String] = [:],
        stackTrace: [String]? = nil
    ) {
        store.client?.captureRailtracks(
            error,
            flowTitle: flowTitle,
            properties: properties,
            stackTrace: stackTrace
        )
    }

    // MARK: - Internal (tests)

    /// Replaces the shared client; the previous one, if any, is flushed in the background.
    static func install(_ client: RailtownClient?) {
        let previous = store.replace(with: client)
        if let previous {
            Task { await previous.flush() }
        }
    }

    /// Clears the shared client without flushing. Tests only.
    static func reset() {
        _ = store.replace(with: nil)
    }
}

/// Lock-guarded slot for the shared client — the SDK's only global state.
///
/// - Note: Marked `@unchecked Sendable`. Safety invariant: `storedClient` is only
///   accessed while holding `lock`, and the lock is never held across a suspension point.
private final class SharedClientStore: @unchecked Sendable {
    private let lock = NSLock()
    private var storedClient: RailtownClient?

    var client: RailtownClient? {
        lock.lock()
        defer { lock.unlock() }
        return storedClient
    }

    func replace(with newClient: RailtownClient?) -> RailtownClient? {
        lock.lock()
        defer { lock.unlock() }
        let previous = storedClient
        storedClient = newClient
        return previous
    }
}
