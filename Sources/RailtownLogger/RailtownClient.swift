//
//  RailtownClient.swift
//  RailtownLogger
//

import Foundation

/// Instance-based client for apps that prefer dependency injection over the
/// ``RailtownLogger`` static facade — the facade delegates every call to one
/// shared instance of this type.
///
/// Capture methods are synchronous and never wait on the network: the entry is
/// rendered on the calling thread (so its stack trace is meaningful) and staged
/// for batched background delivery.
public final class RailtownClient: Sendable {
    private let options: RailtownOptions
    private let entryFactory: LogEntryFactory
    private let dispatcher: any LogDispatching
    private let internalLog: InternalLog

    /// Held for its lifetime: it deregisters its notification observers on deinit.
    private let lifecycleObserver: AppLifecycleObserver?

    /// Creates a client from the `Railtown-Info.plist` bundled with the app — the
    /// Google-services configuration style. The plist needs a single `API_KEY`
    /// string entry holding the key copied from the Railtown platform.
    ///
    /// - Parameters:
    ///   - options: Behavior switches; defaults are production-appropriate.
    ///   - bundle: Where to look for `Railtown-Info.plist`; defaults to the main bundle.
    /// - Throws: ``RailtownLoggerError`` when the plist is missing or its key cannot be parsed.
    public convenience init(
        options: RailtownOptions = RailtownOptions(),
        bundle: Bundle = .main
    ) throws {
        try self.init(apiKey: APIKeyPlistLoader().apiKey(in: bundle), options: options)
    }

    /// Creates a client from the API key copied from the Railtown platform.
    ///
    /// - Parameters:
    ///   - apiKey: The base64 key issued by the platform.
    ///   - options: Behavior switches; defaults are production-appropriate.
    /// - Throws: ``RailtownLoggerError/invalidAPIKey(reason:)`` when the key cannot be parsed.
    public convenience init(apiKey: String, options: RailtownOptions = RailtownOptions()) throws {
        let credentials = try Base64APIKeyParser().parse(apiKey)
        let internalLog = InternalLog(isEnabled: options.isInternalLoggingEnabled)
        self.init(
            options: options,
            entryFactory: LogEntryFactory(
                stackTraceProvider: ThreadStackTraceProvider(),
                contextProvider: RuntimeContextProvider(),
                dateProvider: SystemDateProvider()
            ),
            dispatcher: BatchingDispatcher(
                credentials: credentials,
                flushInterval: options.flushInterval,
                maxBatchSize: options.maxBatchSize,
                maxBufferedEntries: options.maxBufferedEntries,
                retryPolicy: RetryPolicy(maxAttempts: options.maxRetryAttempts),
                payloadBuilder: ConductrPayloadBuilder(),
                httpClient: URLSessionHTTPClient(),
                internalLog: internalLog
            ),
            internalLog: internalLog
        )
    }

    init(
        options: RailtownOptions,
        entryFactory: LogEntryFactory,
        dispatcher: any LogDispatching,
        internalLog: InternalLog
    ) {
        self.options = options
        self.entryFactory = entryFactory
        self.dispatcher = dispatcher
        self.internalLog = internalLog

        guard options.observesAppLifecycle else {
            self.lifecycleObserver = nil
            return
        }
        let timeout = options.flushTimeout
        self.lifecycleObserver = AppLifecycleObserver(
            internalLog: internalLog
        ) { [dispatcher] in
            await dispatcher.flush(timeout: timeout)
        }
    }

    /// Reports an error at ``RailtownLogLevel/error`` level. The error's type,
    /// description, and this call site's stack trace upload as the event's exception.
    ///
    /// - Parameters:
    ///   - error: The error to report.
    ///   - message: Optional event message; defaults to the error's description.
    ///   - properties: Extra key–value context; wins over SDK-provided keys on conflict.
    public func capture(
        _ error: any Error,
        message: RailtownMessage? = nil,
        properties: [String: String] = [:]
    ) {
        stage(
            entryFactory.entry(
                for: error,
                message: message?.rendered,
                level: .error,
                extraProperties: properties
            )
        )
    }

    /// Sends a plain message at the given level.
    ///
    /// - Parameters:
    ///   - message: The message text.
    ///   - level: Severity; defaults to ``RailtownLogLevel/information``.
    ///   - properties: Extra key–value context; wins over SDK-provided keys on conflict.
    public func log(
        _ message: RailtownMessage,
        level: RailtownLogLevel = .information,
        properties: [String: String] = [:]
    ) {
        stage(
            entryFactory.entry(message: message.rendered, level: level, extraProperties: properties)
        )
    }

    /// Uploads everything buffered.
    ///
    /// Gives up after `timeout` seconds — defaulting to
    /// ``RailtownOptions/flushTimeout`` — so a caller racing the system's
    /// suspension deadline is never blocked indefinitely. Anything undelivered
    /// stays buffered for the next attempt rather than being dropped.
    ///
    /// - Parameter timeout: Seconds to wait. `nil` uses the configured default.
    public func flush(timeout: TimeInterval? = nil) async {
        await dispatcher.flush(timeout: timeout ?? options.flushTimeout)
    }

    /// Automatic capture channel used by RailtracksSwift.
    /// Honors the ``RailtownOptions/capturesRailtracksErrors`` switch.
    ///
    /// - Parameters:
    ///   - error: The error that escaped the flow.
    ///   - flowTitle: Display name of the failed flow.
    ///   - properties: Extra key–value context supplied by RailtracksSwift.
    ///   - stackTrace: Optional stack trace RailtracksSwift captured at the throw
    ///     site; when present it replaces the capture-site trace.
    public func captureRailtracks(
        _ error: any Error,
        flowTitle: String,
        properties: [String: String] = [:],
        stackTrace: [String]? = nil
    ) {
        guard options.capturesRailtracksErrors else {
            internalLog.debug("Railtracks auto-capture is disabled — ignoring a flow error.")
            return
        }
        var merged = properties
        merged["FlowTitle"] = flowTitle
        merged["Source"] = "RailtracksSwift"
        stage(
            entryFactory.entry(
                for: error,
                message: "RailtracksSwift flow '\(flowTitle)' failed",
                level: .error,
                extraProperties: merged,
                throwSiteTrace: stackTrace
            )
        )
    }

    // MARK: - Staging

    private func stage(_ entry: LogEntry) {
        mirrorIfEnabled(entry)
        dispatcher.stage(entry)
    }

    /// Writes a text copy of the entry to ``RailtownOptions/entryMirrorDirectory``.
    /// Detached fire-and-forget so capture sites never wait on disk I/O.
    private func mirrorIfEnabled(_ entry: LogEntry) {
        guard let directory = options.entryMirrorDirectory else { return }
        Task.detached(priority: .utility) {
            let fileName = "railtown-entry-"
                + "\(Int(entry.timestamp.timeIntervalSince1970 * 1000))-"
                + "\(UUID().uuidString.prefix(8)).txt"
            let properties = entry.properties
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value)" }
                .joined(separator: "\n")
            var text = "Level: \(entry.level.rawValue)\n\nMessage:\n\(entry.message)\n"
            if let exception = entry.exception {
                text += "\nException:\n\(exception)\n"
            }
            text += "\nProperties:\n\(properties)\n"
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: directory.appendingPathComponent(fileName))
        }
    }
}
