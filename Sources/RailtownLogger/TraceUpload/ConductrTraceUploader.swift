//
//  ConductrTraceUploader.swift
//  RailtownLogger
//

import Combine
import Foundation

/// Uploads agent-run JSON traces to Railtown Conductr via Azure Blob Storage.
///
/// Separate from the log-entry pipeline in every respect: different endpoint, different payload
/// shape, different transport verb. ``RailtownClient`` batches log entries and POSTs them to
/// `https://<host>`; this type exchanges the API key for a short-lived Azure SAS URL and PUTs a
/// single trace file to it.
///
/// Configure before any uploads, then either hand it a file URL directly via
/// ``uploadAgentRun(fileURL:)`` or subscribe to a publisher of trace-file URLs with
/// ``subscribe(to:)-(AnyPublisher<URL,Never>)``.
///
/// Setup mirrors ``RailtownLogger``'s: ``configure(apiBaseURL:isInternalLoggingEnabled:bundle:)``
/// reads the key out of the bundled `Railtown-Info.plist`, and
/// ``configure(apiKey:apiBaseURL:isInternalLoggingEnabled:)`` takes it from the caller — for apps
/// that source the key some other way (remote config, their own storage), which also means
/// reconfiguring wherever the key can change, or a newly-entered key sits unused until the next
/// launch. It keeps its own `configure` rather than sharing
/// ``RailtownLogger/configure(apiKey:options:)`` because `apiBaseURL` cannot be derived from the
/// key: the log pipeline targets the ingestion host packed into the key, while the exchange
/// endpoint lives under a separate API base.
///
/// Not `@MainActor`-isolated — upload work runs on the cooperative pool, keeping network I/O off the
/// main thread.
///
/// - Note: Marked `@unchecked Sendable`. Safety invariant: `configuration`, `internalLog`, and
///   `subscriptions` are only accessed while holding `lock`, and the lock is never held across a
///   suspension point.
public final class ConductrTraceUploader: @unchecked Sendable {
    /// Everything an upload needs, resolved once at configure time so a malformed key fails there
    /// rather than at the first upload.
    private struct Configuration {
        /// The raw base64 key. Retained because `/observe/exchange` takes it as the request *body*;
        /// the parsed ``RailtownCredentials`` cannot substitute for it, and re-encoding the JSON
        /// would not reliably reproduce the issued string. This exposes no secret the credentials
        /// do not already hold — the key is base64 of JSON containing the same authentication code.
        let apiKey: String

        /// Parsed form of `apiKey`, shared with the rest of the SDK.
        let credentials: RailtownCredentials

        /// `apiBaseURL` + `/observe/exchange`, validated at configure time.
        let exchangeURL: URL
    }

    public static let shared = ConductrTraceUploader()

    /// Guards `configuration`, `internalLog`, and `subscriptions`: `configure` is typically called
    /// from the main actor, while publishers deliver and uploads complete on whichever thread they
    /// ran on.
    private let lock = NSLock()
    private var configuration: Configuration?
    private var internalLog = InternalLog(isEnabled: false)

    /// Live trace subscriptions, keyed so a caller can drop its own without touching anyone else's.
    /// Entries remove themselves on completion; ``cancelSubscription(_:)`` clears the ones that will
    /// never complete because their run was cancelled.
    private var subscriptions: [UUID: AnyCancellable] = [:]

    private init() {}

    /// Whether a `configure` call has succeeded — uploads are skipped until it has.
    public var isConfigured: Bool {
        currentConfiguration != nil
    }

    /// Supplies the credentials uploads need, reading the API key from the app's bundled
    /// `Railtown-Info.plist` — the same file ``RailtownLogger/configure(options:bundle:)`` uses, so
    /// both uploaders are set up the same way and neither needs a key in source.
    ///
    /// - Parameters:
    ///   - apiBaseURL: Conductr API base URL. `/observe/exchange` is appended, so it must stop
    ///     at `/api`. Omit it to take the plist's `API_BASE_URL` entry instead; passing one here
    ///     wins over the plist.
    ///   - isInternalLoggingEnabled: Enables this type's diagnostics through `os.Logger`. Off by
    ///     default, matching ``RailtownOptions/isInternalLoggingEnabled``.
    ///   - bundle: Where to look for `Railtown-Info.plist`; defaults to the main bundle.
    /// - Throws: ``RailtownLoggerError/invalidConfigurationPlist(reason:)`` when the plist is
    ///   missing or lacks an entry this call needs, ``RailtownLoggerError/invalidAPIKey(reason:)``
    ///   when the key cannot be parsed, or `URLError(.badURL)` when the base URL does not form a
    ///   valid exchange URL.
    public func configure(
        apiBaseURL: String? = nil,
        isInternalLoggingEnabled: Bool = false,
        bundle: Bundle = .main
    ) throws {
        let loader = APIKeyPlistLoader()
        try configure(
            apiKey: loader.apiKey(in: bundle),
            apiBaseURL: apiBaseURL ?? loader.apiBaseURL(in: bundle),
            isInternalLoggingEnabled: isInternalLoggingEnabled
        )
    }

    /// Supplies the credentials uploads need. Call once at launch with the stored key, and again
    /// whenever the user changes it — the value is cached here, so a key saved mid-session does
    /// nothing until this is called with it.
    ///
    /// - Parameters:
    ///   - apiKey: The base64 key issued by the platform — the same key ``RailtownLogger`` uses.
    ///   - apiBaseURL: Conductr API base URL. `/observe/exchange` is appended, so it must stop
    ///     at `/api`.
    ///   - isInternalLoggingEnabled: Enables this type's diagnostics through `os.Logger`. Off by
    ///     default, matching ``RailtownOptions/isInternalLoggingEnabled``.
    /// - Throws: ``RailtownLoggerError/invalidAPIKey(reason:)`` when the key cannot be parsed, or
    ///   `URLError(.badURL)` when `apiBaseURL` does not form a valid exchange URL.
    public func configure(
        apiKey: String,
        apiBaseURL: String,
        isInternalLoggingEnabled: Bool = false
    ) throws {
        let credentials = try Base64APIKeyParser().parse(apiKey)
        guard let exchangeURL = URL(string: "\(apiBaseURL)/observe/exchange") else {
            throw URLError(.badURL)
        }
        lock.lock()
        configuration = Configuration(
            apiKey: apiKey,
            credentials: credentials,
            exchangeURL: exchangeURL
        )
        internalLog = InternalLog(isEnabled: isInternalLoggingEnabled)
        lock.unlock()
    }

    /// Subscribes to a publisher of trace-file results and uploads the JSON each success points at.
    /// Returns a token for ``cancelSubscription(_:)``, or `nil` when nothing is configured.
    ///
    /// **Subscribe before starting the work that writes the trace, and cancel in a `defer` around
    /// it** — see the `URL` overload for why. A failed trace *write* takes the same path as a
    /// cancelled run here: the `.failure` is logged and filtered out, so no value reaches the
    /// subscription and only the `defer` releases it.
    @discardableResult
    public func subscribe(to publisher: AnyPublisher<Result<URL, any Error>, Never>) -> UUID? {
        let log = currentLog
        return subscribe(
            to: publisher
                .compactMap { result -> URL? in
                    switch result {
                    case .success(let url):
                        return url
                    case .failure(let error):
                        log.error("Trace file URL failed: \(error)")
                        return nil
                    }
                }
                .eraseToAnyPublisher()
        )
    }

    /// Subscribes to a publisher of trace-file URLs and uploads the JSON at each path. Returns a
    /// token for ``cancelSubscription(_:)``, or `nil` when nothing is configured and nothing was
    /// subscribed.
    ///
    /// The publisher is any `AnyPublisher<URL, Never>` — this type has no dependency on what
    /// produces it.
    ///
    /// **Subscribe before starting the work that writes the trace**, and pair it with
    /// ``cancelSubscription(_:)`` in a `defer` around that work.
    ///
    /// A run that writes its trace releases its own subscription: the value arrives, `prefix(1)`
    /// completes, and the entry removes itself. Two cases never emit and so never self-release —
    /// a run cancelled before the trace is written, and a trace whose write failed — and the `defer`
    /// is what stops those waiting forever for a value that isn't coming.
    @discardableResult
    public func subscribe(to publisher: AnyPublisher<URL, Never>) -> UUID? {
        let log = currentLog
        guard currentConfiguration != nil else {
            log.error("Trace uploader is not configured — skipping agent-run upload.")
            return nil
        }
        let token = UUID()
        let cancellable = publisher
            // Load-bearing twice over: it caps this at one upload per publisher, and it's the *only*
            // source of the completion that releases the subscription below. A trace subject that
            // never finishes on its own would strand every subscription without this.
            .prefix(1)
            .sink(
                receiveCompletion: { [weak self] _ in
                    self?.removeSubscription(token)
                },
                receiveValue: { [weak self] url in
                    guard let self else { return }
                    Task {
                        do {
                            guard try await self.uploadAgentRun(fileURL: url) else {
                                log.error("Trace upload failed for file: \(url)")
                                return
                            }
                            log.debug("Trace upload succeeded for file: \(url)")
                        } catch {
                            log.error("Trace upload failed for file: \(url) | error: \(error)")
                        }
                    }
                }
            )
        lock.lock()
        subscriptions[token] = cancellable
        lock.unlock()
        return token
    }

    /// Drops a subscription that will never complete, because its run ended without writing a trace.
    /// A no-op for a run that finished normally — that subscription removed itself — and for `nil`,
    /// so callers can pass ``subscribe(to:)-(AnyPublisher<URL,Never>)``'s result straight through
    /// from a `defer`.
    public func cancelSubscription(_ token: UUID?) {
        guard let token else {
            return
        }
        removeSubscription(token)
    }

    /// Reads the flow-graph JSON at `fileURL`, maps it to the Conductr schema, and uploads it
    /// through a pre-signed SAS URL. `true` when the blob write returned HTTP 201.
    @discardableResult
    public func uploadAgentRun(fileURL: URL) async throws -> Bool {
        guard let configuration = currentConfiguration else {
            throw URLError(.userAuthenticationRequired)
        }
        let log = currentLog
        let data = try Data(contentsOf: fileURL)
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log.error("Failed to parse a JSON trace payload from file: \(fileURL)")
            throw URLError(.cannotParseResponse)
        }
        let credentials = configuration.credentials
        log.debug(
            "Trace upload target — host: \(credentials.host) org: \(credentials.organizationID) "
                + "project: \(credentials.projectID) env: \(credentials.environmentID)"
        )
        let sasURL = try await presignedSASURL(configuration: configuration, log: log)
        return try await uploadToBlobStorage(
            sasURL: sasURL,
            payload: payload,
            sourceURL: fileURL,
            log: log
        )
    }

    // MARK: - Internal (tests)

    /// The exchange URL `configure` resolved, or `nil` when nothing is configured. Tests only —
    /// the only way to see which base URL won.
    var configuredExchangeURL: URL? {
        currentConfiguration?.exchangeURL
    }
}

private extension ConductrTraceUploader {

    /// Releases the subscription for `token`, if one is still held.
    ///
    /// The removed value is deliberately released *outside* the lock: dropping an `AnyCancellable`
    /// runs its `deinit`, which tears down the Combine subscription, and `NSLock` isn't recursive —
    /// so anything in that teardown that came back through here would deadlock rather than merely
    /// misbehave. Nothing does today; this keeps it that way for free.
    func removeSubscription(_ token: UUID) {
        lock.lock()
        let removed = subscriptions.removeValue(forKey: token)
        lock.unlock()
        _ = removed
    }

    /// A snapshot of the configuration, or `nil` if `configure` hasn't been called.
    ///
    /// Explicitly `private`: members of a `private extension` default to `fileprivate`, which the
    /// compiler rejects for anything exposing the private `Configuration` type.
    private var currentConfiguration: Configuration? {
        lock.lock()
        defer {
            lock.unlock()
        }
        return configuration
    }

    /// A snapshot of the diagnostics channel; silent until `configure` enables it.
    var currentLog: InternalLog {
        lock.lock()
        defer {
            lock.unlock()
        }
        return internalLog
    }

    /// Exchanges the API key for a short-lived Azure Blob SAS URL to PUT the trace into.
    ///
    /// - Note: Uses `URLSession` directly rather than the ``HTTPClient`` seam. That protocol is
    ///   POST-only and returns just a status code and body, while this exchange needs the raw key
    ///   as a request body and the blob PUT below needs a different verb and response headers.
    private func presignedSASURL(
        configuration: Configuration,
        log: InternalLog
    ) async throws -> String {
        var request = URLRequest(url: configuration.exchangeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("railtown-swift", forHTTPHeaderField: "User-Agent")
        request.setValue(
            "Bearer \(configuration.credentials.authenticationCode)",
            forHTTPHeaderField: "Authorization"
        )
        // The endpoint takes the key itself as a JSON string body.
        request.httpBody = "\"\(configuration.apiKey)\"".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            log.debug("Trace exchange status: \(httpResponse.statusCode)")
        }
        guard let sasURL = String(data: data, encoding: .utf8) else {
            log.error("Failed to decode the SAS URL response.")
            throw URLError(.cannotParseResponse)
        }
        return sasURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func uploadToBlobStorage(
        sasURL: String,
        payload: [String: Any],
        sourceURL: URL,
        log: InternalLog
    ) async throws -> Bool {
        guard let url = URL(string: sasURL) else {
            log.error("The exchange returned an invalid SAS URL.")
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("2022-11-02", forHTTPHeaderField: "x-ms-version")
        request.setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")

        let run = (payload["runs"] as? [[String: Any]])?.first ?? [:]
        let jsonData = try serializeOrdered(enrichRunWithSession(payload, run: run))
        request.httpBody = jsonData

        log.debug(
            "Trace PUT — size: \(jsonData.count) bytes | source: \(sourceURL.lastPathComponent)"
        )

        let (responseData, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            let status = httpResponse.statusCode
            let requestID = httpResponse.value(forHTTPHeaderField: "x-ms-request-id") ?? "?"
            log.debug("Trace PUT status: \(status) | x-ms-request-id: \(requestID)")
            if status != 201, let body = String(data: responseData, encoding: .utf8) {
                log.error("Trace PUT error body: \(body)")
            }
        }
        return (response as? HTTPURLResponse)?.statusCode == 201
    }

    // MARK: - Conductr JSON schema mapping
    //
    // Flattens the flow-graph trace into the shape the Conductr server expects; mirrors
    // RailtownAI/handler.py.

    func enrichRunWithSession(_ session: [String: Any], run: [String: Any]) -> [String: Any] {
        let currentTime = Int(Date().timeIntervalSince1970 * 1000)
        var enriched: [String: Any] = [:]

        enriched["session_id"] = session["session_id"]
        // Prefer flow_name, then name, then the id — `??` also skips the NSNull a JSON null decodes to.
        enriched["session_name"] = (session["flow_name"] as? String)
            ?? (session["name"] as? String)
            ?? (session["session_id"] as? String)
            ?? "Unknown Session"
        enriched["session_start_time"] = session["start_time"]
        enriched["session_end_time"] = session["end_time"]

        enriched["run_id"] = run["run_id"]
        enriched["run_name"] = run["name"]
        enriched["run_start_time"] = run["start_time"] ?? currentTime
        enriched["run_end_time"] = run["end_time"] ?? currentTime
        enriched["run_status"] = run["status"] ?? "Unknown"

        enriched["nodes"] = run["nodes"]
        enriched["edges"] = run["edges"]
        enriched["steps"] = run["steps"]

        return enriched
    }

    /// Serializes with a fixed key order — the server reads the payload positionally in places, and
    /// `JSONSerialization` gives no ordering guarantee, so the JSON is assembled by hand.
    func serializeOrdered(_ data: [String: Any]) throws -> Data {
        let keyOrder = [
            "session_id", "session_name", "session_start_time", "session_end_time",
            "run_id", "run_name", "run_start_time", "run_end_time", "run_status",
            "nodes", "edges", "steps"
        ]
        var orderedPairs: [(String, Any)] = []
        for key in keyOrder {
            if let value = data[key] {
                orderedPairs.append((key, value))
            }
        }
        for (key, value) in data where !keyOrder.contains(key) {
            orderedPairs.append((key, value))
        }

        var jsonString = "{"
        for (index, (key, value)) in orderedPairs.enumerated() {
            // Wrapped in an array so JSONSerialization accepts primitives (String, Int, NSNull…),
            // then the brackets are stripped to leave just the value's JSON.
            let wrapped = try JSONSerialization.data(withJSONObject: [value])
            guard let wrappedString = String(data: wrapped, encoding: .utf8) else {
                throw URLError(.cannotParseResponse)
            }
            jsonString += "\"\(key)\":\(String(wrappedString.dropFirst().dropLast()))"
            if index < orderedPairs.count - 1 {
                jsonString += ","
            }
        }
        jsonString += "}"
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw URLError(.cannotParseResponse)
        }
        return jsonData
    }
}
