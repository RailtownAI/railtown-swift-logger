//
//  URLSessionHTTPClient.swift
//  RailtownLogger
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// `URLSession`-backed transport.
struct URLSessionHTTPClient: HTTPClient {
    private static let requestTimeout: TimeInterval = 30

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func post(_ body: Data, to url: URL, headers: [String: String]) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = Self.requestTimeout
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await session.data(for: request)
        // No HTTP status means the exchange never reached Conductr in a readable form — a
        // transport-level anomaly, not a rejection. Throwing routes it to `.retryable`;
        // reporting status 0 would hit `RetryPolicy`'s `default: .terminal`, dropping the
        // batch permanently and blaming the server for it in the log.
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return HTTPResponse(statusCode: httpResponse.statusCode, body: data)
    }
}
