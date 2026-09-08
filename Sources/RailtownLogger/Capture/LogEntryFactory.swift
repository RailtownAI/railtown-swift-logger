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
    /// Note the interaction with ``entry(for:message:level:extraProperties:throwSiteTrace:callSite:)``:
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
    /// - Parameters:
    ///   - throwSiteTrace: Optional trace captured at the throw site by the caller;
    ///     when present it replaces this call site's stack.
    ///   - callSite: Where the event originated; uploaded as the `SourceFile`,
    ///     `SourceFunction` and `SourceLine` properties when present.
    func entry(
        for error: any Error,
        message: String?,
        level: RailtownLogLevel,
        extraProperties: [String: String],
        throwSiteTrace: [String]? = nil,
        callSite: CallSite? = nil
    ) -> LogEntry {
        let errorType = Self.qualifiedErrorType(of: error)
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
        callSite?.merge(into: &properties)
        properties.merge(extraProperties) { _, callerValue in callerValue }

        return makeEntry(
            message: resolvedMessage,
            level: level,
            properties: properties,
            exception: exception
        )
    }
    
    /// The error's type, qualified with its enum case when one can be recovered —
    /// `RailtracksSwift.RTSError.missingAPIKey` rather than `RailtracksSwift.RTSError`.
    ///
    /// The case is what identifies *which* failure happened; the type alone groups every failure a
    /// module can produce into one bucket. Three shapes, in the order tried:
    ///
    /// - A case with associated values reports its name as the single child of a `Mirror`.
    /// - A payload-free case has no mirror children, but `String(reflecting:)` renders it as
    ///   `Module.Type.caseName`, so the reflected value is already what's wanted.
    /// - A payload-free case on a type defining its own `description` or `debugDescription` is a
    ///   dead end: `String(reflecting:)` returns that text instead, and the case name isn't
    ///   reachable. Those fall back to the bare type name, as before.
    ///
    /// Struct and class errors fall back to the bare type name. The enum check is load-bearing:
    /// a mirror's first child is the case name *only* for an enum, and for a struct or class it is
    /// the first stored property, which would yield `HTTPError.statusCode` — a name that says
    /// nothing about the failure and, worse, changes whenever a consumer reorders their fields,
    /// splitting one error's history across a release.
    private static func qualifiedErrorType(of error: any Error) -> String {
        let typeName = String(reflecting: type(of: error))
        let mirror = Mirror(reflecting: error)
        let qualified: String
        if mirror.displayStyle == .enum, let caseName = mirror.children.first?.label {
            qualified = "\(typeName).\(caseName)"
        } else {
            let reflected = String(reflecting: error)
            // Both are rendered from the same type, so the prefix check compares like with like —
            // which is why the mangled context is stripped below rather than from `typeName` here.
            qualified = reflected.hasPrefix(typeName + ".") ? reflected : typeName
        }
        return withoutMangledContext(qualified)
    }

    /// `name` with the mangled context Swift renders for non-internal types removed —
    /// `App.(unknown context at $114acc9b4).MyError` becomes `App.MyError`.
    ///
    /// That context holds a **pointer**, freshly assigned each launch, so a `private` or
    /// `fileprivate` error type — an ordinary way to declare one — would otherwise report a
    /// different `ErrorType` every run and scatter one failure across a bucket per app launch.
    /// A function-local type carries two such segments, so every component is filtered, not one.
    ///
    /// - Note: The tradeoff is that two same-named private types in different files of one module
    ///   collapse to a single key. That is the better failure: a rare collision between distinct
    ///   errors, rather than guaranteed fragmentation of every private one.
    private static func withoutMangledContext(_ name: String) -> String {
        guard name.contains("(unknown context at") else {
            return name
        }
        return name
            .split(separator: ".", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("(unknown context at") }
            .joined(separator: ".")
    }

    /// Renders a plain message event (no stack trace).
    func entry(
        message: String,
        level: RailtownLogLevel,
        extraProperties: [String: String],
        callSite: CallSite? = nil
    ) -> LogEntry {
        var properties = contextProvider.contextProperties()
        callSite?.merge(into: &properties)
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
