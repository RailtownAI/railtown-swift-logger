//
//  InternalLog.swift
//  RailtownLogger
//

import Logging

/// Development logger for the RailtownLogger library — the same shape as
/// RailtracksSwift's `RTSLoggers`, so one `LoggingSystem.bootstrap` in the host
/// app governs both. Follows the Swift library log-level guideline:
/// https://www.swift.org/documentation/server/guides/libraries/log-levels.html
enum RailtownLoggers {
    static let logLabel = "railtown.swift.logger.log"
    static let log = Logger(label: RailtownLoggers.logLabel)
}

/// The SDK's own diagnostics channel, gated by
/// ``RailtownOptions/isInternalLoggingEnabled``. Silent unless enabled. Never
/// logs API-key material.
///
/// Output goes wherever the host app's `LoggingSystem` sends it — stdout by
/// default, not the unified log.
struct InternalLog: Sendable {
    private let isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func debug(_ message: String) {
        guard isEnabled else { return }
        RailtownLoggers.log.debug("\(message)")
    }

    func warning(_ message: String) {
        guard isEnabled else { return }
        RailtownLoggers.log.warning("\(message)")
    }

    func error(_ message: String) {
        guard isEnabled else { return }
        RailtownLoggers.log.error("\(message)")
    }
}
