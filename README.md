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

(A second entry, `API_BASE_URL`, is read only by trace uploads — see [Agent-run trace uploads](#agent-run-trace-uploads).)

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
        isInternalLoggingEnabled: false,// SDK diagnostics via os.Logger
        flushTimeout: 5,                // seconds an explicit flush waits before giving up
        observesAppLifecycle: true      // flush automatically on background/terminate
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

Uploads happen on their own: when a batch fills (`maxBatchSize`), when `flushInterval`
elapses, and **automatically when the app backgrounds or terminates** — the SDK observes
those notifications itself, so there is no lifecycle boilerplate to write. On iOS that is
`didEnterBackground` and `willTerminate`; on macOS, where an app keeps running while
unfocused, only `willTerminate` (flushing on every focus change would cost an upload per
cmd-tab).

Turn it off with `observesAppLifecycle: false` if your app manages this itself.

You can still flush at a moment of your choosing:

```swift
await RailtownLogger.flush()              // bounded by options.flushTimeout (5s)
await RailtownLogger.flush(timeout: 15)   // or pass your own bound
```

`flush` is always bounded. iOS allows roughly 30 seconds after backgrounding while a
single request can itself take 30 seconds on a dead network, so an unbounded flush
could not finish in the time the system gives it. When the deadline passes, the
in-flight batch is **returned to the buffer** rather than dropped, and goes out on the
next attempt.

Known limitation: entries still buffered when the process dies are lost. The automatic
flush runs asynchronously, so a process that exits promptly after `willTerminate` takes
the pending upload with it, and a crash or watchdog kill delivers no notification at
all — surviving those needs on-disk spooling, which is not implemented yet.

## RailtracksSwift integration

Apps using [RailtracksSwift](https://github.com/RailtownAI/Railtracks-swift) get automatic capture: any error escaping `flow.run(...)` is uploaded (flow title and Railtracks version attached) and rethrown unchanged. It activates when your app configures `RailtownLogger`; opt out with `capturesRailtracksErrors: false`.

## Agent-run trace uploads

`ConductrTraceUploader` uploads agent-run JSON traces. It is a separate pipeline from error logging — different endpoint, payload, and transport — but it takes the same API key, and it is set up the same way.

**Bundled plist.** Add `API_BASE_URL` alongside `API_KEY` in the same `Railtown-Info.plist` — the Conductr **host only**, since the SDK owns the rest of the path:

```xml
<key>API_BASE_URL</key>
<string>cndr.railtown.ai</string>
```

`https://` is assumed when you leave the scheme off, so `cndr.railtown.ai` and `https://cndr.railtown.ai` are equivalent, and a trailing slash is harmless. Then configure with nothing in source:

```swift
try ConductrTraceUploader.shared.configure()
```

Pass a host to override the plist's — useful when it varies by build configuration:

```swift
try ConductrTraceUploader.shared.configure(apiBaseURL: "testcndr.railtown.ai")
```

**Alternative — key in code.** Same escape hatch as the logger, for keys sourced elsewhere:

```swift
try ConductrTraceUploader.shared.configure(
    apiKey: "<your API key>",
    apiBaseURL: "cndr.railtown.ai"
)
```

Configuration is cached, so call it again whenever the key changes — until you do, a newly-entered key sits unused. Then upload a trace file directly, or subscribe to a publisher that emits them:

```swift
try await ConductrTraceUploader.shared.uploadAgentRun(fileURL: traceFileURL)

let token = ConductrTraceUploader.shared.subscribe(to: tracePublisher)
defer { ConductrTraceUploader.shared.cancelSubscription(token) }
```

Subscribe *before* starting the work that writes the trace, and cancel in a `defer` around it: a run cancelled before it writes a trace never emits, and only the `defer` releases that subscription.

## Dependency injection

The static facade delegates to one shared `RailtownClient`. If you prefer explicit dependencies (or need isolated instances in tests), instantiate the client directly — it has the same API:

```swift
let client = try RailtownClient(apiKey: "<your API key>")
client.capture(error)
await client.flush()
```

## Out of scope (for now)

Crash reporting / dSYM symbolication, disk-persisted offline queueing, and pre-configuration buffering are planned follow-ups.
