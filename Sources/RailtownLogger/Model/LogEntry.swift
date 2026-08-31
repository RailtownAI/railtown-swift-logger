//
//  LogEntry.swift
//  RailtownLogger
//

import Foundation

/// A single log event, fully rendered at capture time and ready to encode.
struct LogEntry: Sendable, Equatable {
    var message: String
    var level: RailtownLogLevel
    var properties: [String: String]
    var timestamp: Date

    /// Error details — type, description, and stack trace. `nil` for plain messages.
    var exception: String? = nil
}
