//
//  LogEntryFactory.swift
//  RailtownLogger
//

import Foundation

/// Turns raw capture inputs into fully rendered ``LogEntry`` values.
///
/// Runs synchronously on the caller's thread so the captured stack trace
/// reflects the capture site rather than SDK machinery.
struct LogEntryFactory: Sendable {
    /// Caps guarding against pathological inputs producing megabyte uploads.
    ///
    /// Note the interaction with ``entry(for:message:level:extraProperties:throwSiteTrace:)``:
    /// `exception` is assembled as the error headline followed by the stack trace, then
    /// truncated with `prefix`, which keeps the front. An error whose `String(describing:)`
    /// output approaches `maxMessageLength` therefore crowds the frames out of the upload
    /// entirely — a large description can leave no trace at all.
    ///
    /// Accepted trade-off, not an oversight: the error's type and description identify *what*
    /// failed, which is worth more than *where* when only one of the two fits. If a case turns
    /// up where the trace matters more than an oversized description, budget the headline and
    /// the frames separately rather than raising the cap.
    private static let maxMessageLength = 32_768
    private static let maxPropertyValueLength = 8_192

    private let stackTraceProvider: any StackTraceProviding
    private let contextProvider: any RuntimeContextProviding
    private let dateProvider: any DateProviding

    init(
        stackTraceProvider: any StackTraceProviding,
        contextProvider: any RuntimeContextProviding,
        dateProvider: any DateProviding
    ) {
        self.stackTraceProvider = stackTraceProvider
        self.contextProvider = contextProvider
        self.dateProvider = dateProvider
    }

    /// Renders an error event: the caller's message (or the error headline) as
    /// `message`, the error type + description + stack trace as `exception`, and
    /// structured context in the properties.
    ///
    /// - Parameter throwSiteTrace: Optional trace captured at the throw site by the
    ///   caller; when present it replaces this call site's stack.
    func entry(
        for error: any Error,
        message: String?,
        level: RailtownLogLevel,
        extraProperties: [String: String],
        throwSiteTrace: [String]? = nil
    ) -> LogEntry {
        let errorType = String(reflecting: type(of: error))
        // String(describing:) preserves enum case names and associated values,
        // where localizedDescription collapses most Swift errors to a generic sentence.
        let headline = "\(errorType): \(String(describing: error))"

        // Exception carries the error details + stack trace, in the exact shape the
        // Conductr parser expects (RailtownLogger#1); a trace captured at the throw
        // site beats this call site's stack.
        let frames = throwSiteTrace ?? stackTraceProvider.currentStackTrace()
        // Headline first, frames second — truncation drops from the tail, so an oversized
        // description wins over the trace. See `maxMessageLength`.
        let exception = headline + "\n\nStack trace:\n" + frames.joined(separator: "\n")

        let resolvedMessage: String
        if let message, !message.isEmpty {
            resolvedMessage = message
        } else {
            resolvedMessage = headline
        }

        var properties = contextProvider.contextProperties()
        properties["ErrorType"] = errorType
        properties["ErrorDescription"] = error.localizedDescription
        properties.merge(extraProperties) { _, callerValue in callerValue }

        return makeEntry(
            message: resolvedMessage,
            level: level,
            properties: properties,
            exception: exception
        )
    }

    /// Renders a plain message event (no stack trace).
    func entry(
        message: String,
        level: RailtownLogLevel,
        extraProperties: [String: String]
    ) -> LogEntry {
        var properties = contextProvider.contextProperties()
        properties.merge(extraProperties) { _, callerValue in callerValue }
        return makeEntry(message: message, level: level, properties: properties)
    }

    private func makeEntry(
        message: String,
        level: RailtownLogLevel,
        properties: [String: String],
        exception: String? = nil
    ) -> LogEntry {
        LogEntry(
            message: String(message.prefix(Self.maxMessageLength)),
            level: level,
            properties: properties.mapValues { String($0.prefix(Self.maxPropertyValueLength)) },
            timestamp: dateProvider.now,
            exception: exception.map { String($0.prefix(Self.maxMessageLength)) }
        )
    }
}
