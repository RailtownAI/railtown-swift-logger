//
//  RetryPolicyTests.swift
//  RailtownLoggerTests
//

import Foundation
import Testing
@testable import RailtownLogger

@Suite struct RetryPolicyTests {
    private static let classificationCases: [(statusCode: Int, expected: SendOutcome)] = [
        (200, .success), (201, .success), (204, .success), (299, .success),
        (408, .retryable), (429, .retryable),
        (500, .retryable), (502, .retryable), (503, .retryable), (599, .retryable),
        (400, .terminal), (401, .terminal), (403, .terminal), (404, .terminal),
        (405, .terminal), (409, .terminal), (422, .terminal),
        (301, .terminal), (0, .terminal),
    ]

    @Test(arguments: classificationCases)
    func classifiesStatusCodes(_ testCase: (statusCode: Int, expected: SendOutcome)) {
        let policy = RetryPolicy(maxAttempts: 3)
        #expect(policy.outcome(forStatusCode: testCase.statusCode) == testCase.expected)
    }

    @Test func delaysGrowExponentiallyUpToTheCap() {
        let policy = RetryPolicy(maxAttempts: 10, baseDelay: 0.5, maxDelay: 30)
        #expect(policy.delay(afterAttempt: 1) == 0.5)
        #expect(policy.delay(afterAttempt: 2) == 1.0)
        #expect(policy.delay(afterAttempt: 3) == 2.0)
        #expect(policy.delay(afterAttempt: 4) == 4.0)
        #expect(policy.delay(afterAttempt: 7) == 30.0)
        #expect(policy.delay(afterAttempt: 20) == 30.0)
    }

    @Test func enforcesAtLeastOneAttempt() {
        #expect(RetryPolicy(maxAttempts: 0).maxAttempts == 1)
        #expect(RetryPolicy(maxAttempts: -3).maxAttempts == 1)
    }
}
