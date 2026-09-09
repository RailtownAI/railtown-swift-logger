//
//  InternalLog.swift
//  RailtownLogger
//

import Logging

/// Labels for the SDK's swift-log loggers — the same stack RailtracksSwift uses
/// (`railtracks.swift.log`), so one `LoggingSystem.bootstrap` in the host app
/// governs both.
enum RailtownLoggers {
    /// Filter on this label in a custom `LogHandler` to isolate SDK diagnostics.
    static let logLabel = "railtown.swift.logger.log"
}

/// The SDK's own diagnostics channel. Never logs API-key material.
///
/// Backed by swift-log: messages go wherever the host app's `LoggingSystem`
/// sends them — stdout by default, not the unified log, so they will not appear
/// in Console.app or `log stream` unless the app installs an OSLog-backed handler.
///
/// ``RailtownOptions/isInternalLoggingEnabled`` sets the level: enabled lets
/// everything from `.debug` up through; disabled raises the floor to `.critical`,
/// a level the SDK never emits at, which keeps it silent by default.
struct InternalLog: Sendable {
    private let logger: Logger

    init(isEnabled: Bool) {
        var logger = Logger(label: RailtownLoggers.logLabel)
        logger.logLevel = isEnabled ? .debug : .critical
        self.logger = logger
    }

    func debug(_ message: String) {
        logger.debug("\(message)")
    }

    func warning(_ message: String) {
        logger.warning("\(message)")
    }

    func error(_ message: String) {
        logger.error("\(message)")
    }
}
