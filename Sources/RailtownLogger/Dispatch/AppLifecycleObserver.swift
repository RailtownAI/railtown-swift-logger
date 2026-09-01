//
//  AppLifecycleObserver.swift
//  RailtownLogger
//

import Foundation
#if canImport(UIKit) && !os(watchOS)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Flushes buffered entries when the app leaves the foreground or terminates,
/// so an integrator does not have to remember to.
///
/// Delivery is best-effort: the flush runs in a detached task, so a process that
/// exits promptly takes the pending upload with it, and a crash or watchdog kill
/// delivers no notification at all. Surviving those needs on-disk spooling,
/// which this SDK does not yet do.
///
/// - Note: Marked `@unchecked Sendable`. Safety invariant: `tokens` is immutable
///   after `init`, and `NotificationCenter` observer tokens may be removed from
///   any thread.
final class AppLifecycleObserver: @unchecked Sendable {
    /// Tokens returned by block-based observation.
    ///
    /// They must be retained and handed back to `removeObserver`: that API
    /// matches on the token, not on the observing object, so `removeObserver(self)`
    /// silently leaves the blocks registered and firing after this object is gone.
    private let tokens: [any NSObjectProtocol]
    private let notificationCenter: NotificationCenter

    /// - Parameters:
    ///   - names: Notifications to flush on; defaults to the platform's
    ///     lifecycle transitions.
    ///   - notificationCenter: Where to observe; injectable so tests do not
    ///     share the process-wide center.
    ///   - internalLog: Diagnostics channel; the flush is otherwise invisible.
    ///   - flush: Invoked when the app backgrounds or terminates.
    init(
        names: [Notification.Name] = AppLifecycleObserver.lifecycleNotificationNames,
        notificationCenter: NotificationCenter = .default,
        internalLog: InternalLog = InternalLog(isEnabled: false),
        flush: @escaping @Sendable () async -> Void
    ) {
        self.notificationCenter = notificationCenter
        tokens = names.map { name in
            notificationCenter.addObserver(forName: name, object: nil, queue: nil) { _ in
                internalLog.debug("\(name.rawValue) — flushing buffered entries.")
                Task {
                    await flush()
                    internalLog.debug("\(name.rawValue) — flush finished.")
                }
            }
        }
    }

    deinit {
        for token in tokens {
            notificationCenter.removeObserver(token)
        }
    }

    /// Transitions worth flushing on for the current platform.
    ///
    /// Internal rather than private so tests can post whatever the current
    /// platform actually observes.
    static var lifecycleNotificationNames: [Notification.Name] {
        #if canImport(UIKit) && !os(watchOS)
        [
            UIApplication.didEnterBackgroundNotification,
            UIApplication.willTerminateNotification,
        ]
        #elseif canImport(AppKit)
        // Deliberately not `willResignActive`: it fires on every focus change,
        // so each cmd-tab would cost an upload. A Mac app stays running, and the
        // flush interval already covers steady-state delivery.
        [NSApplication.willTerminateNotification]
        #else
        []
        #endif
    }
}
