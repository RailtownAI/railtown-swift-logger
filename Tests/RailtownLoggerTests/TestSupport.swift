//
//  TestSupport.swift
//  RailtownLoggerTests
//

import Foundation
@testable import RailtownLogger

// MARK: - Fixtures

enum TestError: Error {
    case boom(String)
}

enum TestFixtures {
    /// Builds a syntactically valid API key with test values.
    static func makeKey(host: String = "example.railtownlogs.com") -> String {
        let json = """
        {"u":"\(host)","o":"org-123","p":"proj-456","h":"auth-code==","e":"env-789"}
        """
        return Data(json.utf8).base64EncodedString()
    }

    /// Credentials matching ``makeKey(host:)``, produced through the real parser.
    static func makeCredentials() throws -> RailtownCredentials {
        try Base64APIKeyParser().parse(makeKey())
    }

    struct FixtureError: Error {}

    /// Builds a throwaway directory-bundle, optionally containing a `Railtown-Info.plist`
    /// with the given contents.
    static func makeBundle(plistContents: [String: Any]?) throws -> Bundle {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("railtown-plist-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let plistContents {
            let data = try PropertyListSerialization.data(
                fromPropertyList: plistContents,
                format: .xml,
                options: 0
            )
            try data.write(to: directory.appendingPathComponent("Railtown-Info.plist"))
        }
        guard let bundle = Bundle(path: directory.path) else {
            throw FixtureError()
        }
        return bundle
    }
}

// MARK: - Mocks

/// Scriptable HTTP transport that records every request. Once the script is
/// exhausted, every request receives `fallback`.
actor MockHTTPClient: HTTPClient {
    enum ScriptedResult {
        case status(Int)
        case failure(any Error)
    }

    struct RecordedRequest: Sendable {
        let body: Data
        let url: URL
        let headers: [String: String]
    }

    private(set) var requests: [RecordedRequest] = []
    private var script: [ScriptedResult]
    private let fallback: ScriptedResult

    init(script: [ScriptedResult] = [], fallback: ScriptedResult = .status(200)) {
        self.script = script
        self.fallback = fallback
    }

    var requestCount: Int { requests.count }

    func post(_ body: Data, to url: URL, headers: [String: String]) async throws -> HTTPResponse {
        requests.append(RecordedRequest(body: body, url: url, headers: headers))
        let result = script.isEmpty ? fallback : script.removeFirst()
        switch result {
        case .status(let statusCode):
            return HTTPResponse(statusCode: statusCode, body: Data())
        case .failure(let error):
            throw error
        }
    }
}

struct FixedDateProvider: DateProviding {
    let now: Date
}

struct FixedStackTraceProvider: StackTraceProviding {
    let lines: [String]
    func currentStackTrace() -> [String] { lines }
}

struct FixedContextProvider: RuntimeContextProviding {
    let properties: [String: String]
    func contextProperties() -> [String: String] { properties }
}

// MARK: - Helpers

/// Polls `condition` until it holds or `timeout` elapses. Avoids fixed sleeps in
/// timing-sensitive dispatcher tests.
func eventually(
    timeout: TimeInterval = 2,
    _ condition: @Sendable () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return await condition()
}

/// Decodes uploaded payloads for assertions, mirroring what the backend would parse.
enum PayloadInspector {
    static func envelopes(in data: Data) -> [[String: Any]] {
        (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
    }

    static func body(of envelope: [String: Any]) -> [String: Any] {
        guard
            let bodyString = envelope["Body"] as? String,
            let body = (try? JSONSerialization.jsonObject(with: Data(bodyString.utf8)))
                as? [String: Any]
        else { return [:] }
        return body
    }

    static func messages(in data: Data) -> [String] {
        envelopes(in: data).compactMap { body(of: $0)["Message"] as? String }
    }
}
