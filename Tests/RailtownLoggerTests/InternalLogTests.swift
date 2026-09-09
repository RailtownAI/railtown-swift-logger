//
//  InternalLogTests.swift
//  RailtownLoggerTests
//

import Foundation
import Logging
import Testing
@testable import RailtownLogger

/// A swift-log handler that records what reaches it, so the level gate can be
/// observed through swift-log's own filtering rather than inferred.
private final class RecordingHandler: LogHandler, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(Logger.Level, String)] = []
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .trace

    var entries: [(Logger.Level, String)] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?,
             source: String, file: String, function: String, line: UInt) {
        lock.lock(); defer { lock.unlock() }
        recorded.append((level, message.description))
    }
}

@Suite struct InternalLogTests {
    private func makeLog(isEnabled: Bool) -> (InternalLog, RecordingHandler) {
        let handler = RecordingHandler()
        let logger = Logger(label: RailtownLoggers.logLabel) { _ in handler }
        return (InternalLog(isEnabled: isEnabled, logger: logger), handler)
    }

    @Test func enabledLetsDebugThrough() {
        #expect(InternalLog(isEnabled: true).logLevel == .debug)
    }

    /// Off by default means silent: the floor sits above every level the SDK emits at.
    @Test func disabledRaisesTheFloorAboveEverythingTheSDKEmits() {
        let level = InternalLog(isEnabled: false).logLevel
        #expect(level == .critical)
        #expect(level > .error)
    }

    @Test func enabledDeliversEveryLevelTheSDKUses() {
        let (log, handler) = makeLog(isEnabled: true)
        log.debug("d"); log.warning("w"); log.error("e")

        #expect(handler.entries.map(\.0) == [.debug, .warning, .error])
        #expect(handler.entries.map(\.1) == ["d", "w", "e"])
    }

    /// The gate is swift-log's own level check, so nothing reaches the handler at all.
    @Test func disabledDeliversNothing() {
        let (log, handler) = makeLog(isEnabled: false)
        log.debug("d"); log.warning("w"); log.error("e")

        #expect(handler.entries.isEmpty)
    }

    @Test func usesTheRailtownLabelSoAppsCanFilterIt() {
        #expect(RailtownLoggers.logLabel == "railtown.swift.logger.log")
    }
}
