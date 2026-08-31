# RailtownLogger

Swift SDK for [Railtown AI](https://railtown.ai) error collection: capture errors (with stack-trace text) and messages from your app — or automatically from RailtracksSwift — and deliver them to Conductr in batched background uploads.

## Requirements

- Swift 6 (tools 6.3)
- iOS 15+ / macOS 12+ / tvOS 15+ / watchOS 8+ / visionOS 1+
- No external dependencies

## Installation

Add the package to your `Package.swift`:

```swift
.package(url: "https://github.com/RailtownAI/railtown-swift-logger", exact: "0.2.0"),
```

and `"RailtownLogger"` to your target's dependencies. In Xcode: **File → Add Package Dependencies…** with the same URL.

## Setup

**Recommended — bundled plist (Google-services style).** Add a `Railtown-Info.plist` file to your app target with one entry, `API_KEY`, holding the key copied from the Railtown platform:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>API_KEY</key>
	<string>PASTE-YOUR-RAILTOWN-API-KEY-HERE</string>
</dict>
</plist>
```

Then configure once before your app launches — no key in source:

```swift
import RailtownLogger

@main
struct MyApp: App {
    init() {
        do {
            try RailtownLogger.configure()
        } catch {
            // Plist missing or key malformed — nothing will be uploaded.
            print("RailtownLogger configuration failed: \(error)")
        }
    }
    // ...
}
```

**Alternative — key in code.** Pass the key directly if you source it some other way (remote config, your own storage):

```swift
try RailtownLogger.configure(apiKey: "<your API key>")
```

Every option has a production-appropriate default; override what you need:

```swift
try RailtownLogger.configure(
    apiKey: "<your API key>",
    options: RailtownOptions(
        capturesRailtracksErrors: true, // auto-upload errors escaping RailtracksSwift flows
        flushInterval: 5,               // seconds a buffered entry waits at most
        maxBatchSize: 20,               // entries per upload
        maxBufferedEntries: 500,        // buffer cap; oldest dropped beyond it
        maxRetryAttempts: 5,            // delivery attempts before a batch is dropped
        isInternalLoggingEnabled: false // SDK diagnostics via os.Logger
    )
)
```

## Capturing errors and messages

```swift
do {
    try await checkout()
} catch {
    // Uploads at error level; the error and this call site's stack trace
    // travel as the event's exception.
    RailtownLogger.capture(error, properties: ["Screen": "Checkout"])
    // Or with extra context:
    RailtownLogger.capture(error, message: "Checkout failed", properties: ["OrderId": order.id])
}

// Plain messages at any level:
RailtownLogger.log("Sync finished", level: .information, properties: ["Items": "\(count)"])
```

Capture calls are synchronous and never wait on the network — entries are staged on the calling thread and uploaded in batches in the background. Before `configure` succeeds, every call is a safe no-op.

The stack trace is captured by the SDK (`Thread.callStackSymbols`) at the moment of the `capture` call, so callers never assemble one; it uploads in the event's `Exception` field together with the error's type and description. Note that in `async` code the frames above the current suspension point belong to the concurrency runtime; the structured properties (`ErrorType`, `ErrorDescription`, app and OS versions, plus your own) carry the reliable context. The SDK's own version is not among them — it travels separately as the envelope's `ClientVersion`.

## Flushing

Uploads happen automatically (batch full, or `flushInterval` elapsed). To minimize loss when the app is suspended, flush on backgrounding:

```swift
.onChange(of: scenePhase) { _, phase in
    if phase == .background {
        Task { await RailtownLogger.flush() }
    }
}
```

Known limitation: entries still buffered when the process is killed are lost (no disk persistence yet).

## RailtracksSwift integration

Apps using [RailtracksSwift](https://github.com/RailtownAI/Railtracks-swift) get automatic capture: any error escaping `flow.run(...)` is uploaded (flow title and Railtracks version attached) and rethrown unchanged. It activates when your app configures `RailtownLogger`; opt out with `capturesRailtracksErrors: false`.

## Dependency injection

The static facade delegates to one shared `RailtownClient`. If you prefer explicit dependencies (or need isolated instances in tests), instantiate the client directly — it has the same API:

```swift
let client = try RailtownClient(apiKey: "<your API key>")
client.capture(error)
await client.flush()
```

## Out of scope (for now)

Crash reporting / dSYM symbolication, disk-persisted offline queueing, and pre-configuration buffering are planned follow-ups.
