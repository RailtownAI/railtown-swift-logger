//
//  AppLifecycleObserverTests.swift
//  RailtownLoggerTests
//

import Foundation
import Testing
@testable import RailtownLogger

@Suite struct AppLifecycleObserverTests {
    /// Counts flushes triggered from the notification blocks.
    private actor FlushCounter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    /// Each test observes its own center, so parallel tests cannot post into
    /// one another's observers.
    private func makeChannel() -> (NotificationCenter, Notification.Name) {
        (NotificationCenter(), Notification.Name("railtown.lifecycle.test"))
    }

    @Test func flushesWhenALifecycleNotificationArrives() async throws {
        let (center, name) = makeChannel()
        let counter = FlushCounter()
        let observer = AppLifecycleObserver(names: [name], notificationCenter: center) {
            await counter.increment()
        }

        center.post(name: name, object: nil)

        #expect(await eventually { await counter.count == 1 })
        _ = observer
    }

    /// `removeObserver(self)` does not unregister block-based observation — it
    /// matches on the returned token instead. Getting this wrong leaves a
    /// deallocated client's blocks firing forever, which reconfiguring the SDK
    /// would hit.
    @Test func stopsFlushingOnceDeallocated() async throws {
        let (center, name) = makeChannel()
        let counter = FlushCounter()

        do {
            let observer = AppLifecycleObserver(names: [name], notificationCenter: center) {
                await counter.increment()
            }
            center.post(name: name, object: nil)
            #expect(await eventually { await counter.count == 1 })
            _ = observer
        }

        center.post(name: name, object: nil)

        // Give a leaked block time to fire before concluding it did not.
        try await Task.sleep(seconds: 0.2)
        #expect(await counter.count == 1)
    }

    @Test func observesTheExpectedTransitionsForThePlatform() {
        let names = AppLifecycleObserver.lifecycleNotificationNames.map(\.rawValue)
        #if os(iOS) || os(tvOS) || os(visionOS)
        #expect(names.contains("UIApplicationDidEnterBackgroundNotification"))
        #expect(names.contains("UIApplicationWillTerminateNotification"))
        #elseif os(macOS)
        #expect(names == ["NSApplicationWillTerminateNotification"])
        #endif
    }
}
