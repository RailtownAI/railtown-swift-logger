//
//  CallSite.swift
//  RailtownLogger
//

/// Where in the source an event originated.
///
/// For ``RailtownLogger/capture(_:message:properties:file:function:line:)`` and
/// ``RailtownLogger/log(_:level:properties:file:function:line:)`` the compiler
/// fills this in at the call site through `#fileID` / `#function` / `#line`
/// default arguments, so it costs nothing at runtime and — unlike stack-trace
/// symbols — survives symbol stripping in release builds.
///
/// Libraries that record where an error was *raised* (RailtracksSwift does, on
/// `RTSError`) pass that location explicitly, so the report points at the code
/// that failed rather than the code that reported it.
public struct CallSite: Sendable, Equatable {
    /// `Module/File.swift` — `#fileID` rather than `#file`, so no absolute build
    /// path from the developer's machine is ever uploaded.
    public let file: String

    /// The enclosing function, e.g. `checkout(order:)`.
    public let function: String

    /// Line number of the call.
    public let line: Int

    public init(file: String, function: String, line: Int) {
        self.file = file
        self.function = function
        self.line = line
    }

    /// Property keys used on the wire.
    enum Key {
        static let file = "SourceFile"
        static let function = "SourceFunction"
        static let line = "SourceLine"
    }

    func merge(into properties: inout [String: String]) {
        properties[Key.file] = file
        properties[Key.function] = function
        properties[Key.line] = String(line)
    }
}
