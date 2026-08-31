//
//  RailtownOptions.swift
//  RailtownLogger
//

import Foundation

/// Behavior switches for the Railtown logger, supplied once at configure time.
public struct RailtownOptions: Sendable {
    /// When true (the default), errors escaping RailtracksSwift flows are uploaded automatically.
    public var capturesRailtracksErrors: Bool

    /// Longest time a buffered entry waits before an upload is attempted.
    public var flushInterval: TimeInterval

    /// Number of buffered entries that triggers an immediate upload.
    public var maxBatchSize: Int

    /// Upper bound on buffered entries; beyond it the oldest entries are dropped.
    public var maxBufferedEntries: Int

    /// Number of delivery attempts for a batch before it is dropped.
    public var maxRetryAttempts: Int

    /// Enables the SDK's own diagnostic logging through `os.Logger`. Off by default.
    public var isInternalLoggingEnabled: Bool

    /// Debug aid: when set, every staged entry's rendered message and properties are
    /// also written as a text file into this directory — exactly what gets uploaded,
    /// available for local inspection. Intended for development builds; leave `nil`
    /// in production.
    public var entryMirrorDirectory: URL?

    /// Creates options, defaulting every knob to production-appropriate values.
    ///
    /// - Parameters:
    ///   - capturesRailtracksErrors: Auto-upload switch for errors escaping RailtracksSwift flows.
    ///   - flushInterval: Longest time a buffered entry waits before an upload is attempted.
    ///   - maxBatchSize: Buffered-entry count that triggers an immediate upload.
    ///   - maxBufferedEntries: Buffer capacity; the oldest entries are dropped beyond it.
    ///   - maxRetryAttempts: Delivery attempts for a batch before it is dropped.
    ///   - isInternalLoggingEnabled: Enables the SDK's own diagnostic logging.
    ///   - entryMirrorDirectory: Debug aid — directory that receives a text copy of every
    ///     staged entry. Leave `nil` in production.
    public init(
        capturesRailtracksErrors: Bool = true,
        flushInterval: TimeInterval = 5,
        maxBatchSize: Int = 20,
        maxBufferedEntries: Int = 500,
        maxRetryAttempts: Int = 5,
        isInternalLoggingEnabled: Bool = false,
        entryMirrorDirectory: URL? = nil
    ) {
        self.capturesRailtracksErrors = capturesRailtracksErrors
        self.flushInterval = flushInterval
        self.maxBatchSize = maxBatchSize
        self.maxBufferedEntries = maxBufferedEntries
        self.maxRetryAttempts = maxRetryAttempts
        self.isInternalLoggingEnabled = isInternalLoggingEnabled
        self.entryMirrorDirectory = entryMirrorDirectory
    }
}
