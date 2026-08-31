//
//  RailtownLogLevel.swift
//  RailtownLogger
//

/// Severity of a log event, on the scale the Conductr backend expects
/// (Serilog-compatible: `verbose` = 0 through `fatal` = 5).
public enum RailtownLogLevel: Int, Sendable, Codable, Hashable, CaseIterable {
    case verbose = 0
    case debug = 1
    case information = 2
    case warning = 3
    case error = 4
    case fatal = 5
}
