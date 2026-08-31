//
//  InternalLog.swift
//  RailtownLogger
//

import os

/// The SDK's own diagnostics channel. Silent unless enabled in ``RailtownOptions``.
/// Never logs API-key material.
struct InternalLog: Sendable {
    private let isEnabled: Bool
    private let logger = Logger(subsystem: "com.railtown.logger", category: "RailtownLogger")

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func debug(_ message: String) {
        guard isEnabled else { return }
        logger.debug("\(message, privacy: .public)")
    }

    func warning(_ message: String) {
        guard isEnabled else { return }
        logger.warning("\(message, privacy: .public)")
    }

    func error(_ message: String) {
        guard isEnabled else { return }
        logger.error("\(message, privacy: .public)")
    }
}
