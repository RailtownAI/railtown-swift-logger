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

    /// Whether the SDK flushes automatically when the app backgrounds or
    /// terminates. On by default, so integrators do not have to wire it up.
    ///
    /// Turn it off only if your app manages the lifecycle itself; nothing else
    /// observes those notifications, so buffered entries would then rely on the
    /// batch-size and interval triggers alone.
    public var observesAppLifecycle: Bool

    /// How long ``RailtownLogger/flush(timeout:)`` waits before giving up.
    ///
    /// iOS allows roughly 30 seconds after backgrounding, and a single request can
    /// take 30 seconds on a dead network, so an unbounded flush cannot finish in
    /// the time the system gives it. Undelivered entries stay buffered.
    public var flushTimeout: TimeInterval

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
    ///   - flushTimeout: How long an explicit flush waits before giving up.
    ///   - observesAppLifecycle: Flush automatically on background/terminate.
    ///   - entryMirrorDirectory: Debug aid — directory that receives a text copy of every
    ///     staged entry. Leave `nil` in production.
    public init(
        capturesRailtracksErrors: Bool = true,
        flushInterval: TimeInterval = 5,
        maxBatchSize: Int = 20,
        maxBufferedEntries: Int = 500,
        maxRetryAttempts: Int = 5,
        isInternalLoggingEnabled: Bool = false,
        flushTimeout: TimeInterval = 5,
        observesAppLifecycle: Bool = true,
        entryMirrorDirectory: URL? = nil
    ) {
        self.capturesRailtracksErrors = capturesRailtracksErrors
        self.flushInterval = flushInterval
        self.maxBatchSize = maxBatchSize
        self.maxBufferedEntries = maxBufferedEntries
        self.maxRetryAttempts = maxRetryAttempts
        self.isInternalLoggingEnabled = isInternalLoggingEnabled
        self.flushTimeout = flushTimeout
        self.observesAppLifecycle = observesAppLifecycle
        self.entryMirrorDirectory = entryMirrorDirectory
    }
}
