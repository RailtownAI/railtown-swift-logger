//
//  RetryPolicy.swift
//  RailtownLogger
//

import Foundation

/// How a completed send attempt should be handled.
enum SendOutcome: Sendable, Equatable {
    case success
    case retryable
    case terminal
}

/// Pure classification and backoff rules for batch delivery.
struct RetryPolicy: Sendable {
    /// Total attempts (first try included) before a batch is dropped.
    var maxAttempts: Int
    var baseDelay: TimeInterval
    var maxDelay: TimeInterval

    init(maxAttempts: Int, baseDelay: TimeInterval = 0.5, maxDelay: TimeInterval = 30) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    /// Classifies an HTTP status code: 2xx succeeded; 408/429/5xx are worth retrying;
    /// any other status is terminal — the batch will never be accepted, so drop it.
    func outcome(forStatusCode statusCode: Int) -> SendOutcome {
        switch statusCode {
        case 200..<300: .success
        case 408, 429: .retryable
        case 500..<600: .retryable
        default: .terminal
        }
    }

    /// Exponential backoff before retrying after the given 1-based failed attempt,
    /// capped at `maxDelay`: 0.5 s, 1 s, 2 s, 4 s, …
    func delay(afterAttempt attempt: Int) -> TimeInterval {
        min(baseDelay * pow(2, Double(max(1, attempt) - 1)), maxDelay)
    }
}
