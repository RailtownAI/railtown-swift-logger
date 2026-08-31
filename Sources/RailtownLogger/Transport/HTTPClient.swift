//
//  HTTPClient.swift
//  RailtownLogger
//

import Foundation

/// Result of a completed HTTP exchange.
struct HTTPResponse: Sendable {
    let statusCode: Int
    let body: Data
}

/// Minimal HTTP transport seam. Production uses ``URLSessionHTTPClient``;
/// tests substitute a scriptable mock.
protocol HTTPClient: Sendable {
    /// POSTs `body` to `url` and returns the server's response.
    /// - Throws: Transport-level failures (connectivity, DNS, timeout).
    func post(_ body: Data, to url: URL, headers: [String: String]) async throws -> HTTPResponse
}
