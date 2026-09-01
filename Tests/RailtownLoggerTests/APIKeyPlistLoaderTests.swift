//
//  APIKeyPlistLoaderTests.swift
//  RailtownLoggerTests
//

import Foundation
import Testing
@testable import RailtownLogger

@Suite struct APIKeyPlistLoaderTests {
    private let loader = APIKeyPlistLoader()

    @Test func readsTheAPIKeyEntry() throws {
        let bundle = try TestFixtures.makeBundle(plistContents: ["API_KEY": TestFixtures.makeKey()])
        #expect(try loader.apiKey(in: bundle) == TestFixtures.makeKey())
    }

    @Test func rejectsABundleWithoutThePlist() throws {
        let bundle = try TestFixtures.makeBundle(plistContents: nil)
        #expect(throws: RailtownLoggerError.self) {
            try loader.apiKey(in: bundle)
        }
    }

    @Test func rejectsAPlistWithoutTheEntry() throws {
        let bundle = try TestFixtures.makeBundle(plistContents: ["SOMETHING_ELSE": "value"])
        #expect(throws: RailtownLoggerError.self) {
            try loader.apiKey(in: bundle)
        }
    }

    @Test func rejectsAnEmptyKeyEntry() throws {
        let bundle = try TestFixtures.makeBundle(plistContents: ["API_KEY": ""])
        #expect(throws: RailtownLoggerError.self) {
            try loader.apiKey(in: bundle)
        }
    }

    @Test func readsTheAPIBaseURLEntry() throws {
        let bundle = try TestFixtures.makeBundle(
            plistContents: ["API_KEY": TestFixtures.makeKey(), "API_BASE_URL": TestFixtures.baseURL]
        )
        #expect(try loader.apiBaseURL(in: bundle) == TestFixtures.baseURL)
    }

    @Test func rejectsAPlistWithoutTheBaseURLEntry() throws {
        let bundle = try TestFixtures.makeBundle(plistContents: ["API_KEY": TestFixtures.makeKey()])
        #expect(throws: RailtownLoggerError.self) {
            try loader.apiBaseURL(in: bundle)
        }
    }

    @Test func rejectsAnEmptyBaseURLEntry() throws {
        let bundle = try TestFixtures.makeBundle(
            plistContents: ["API_KEY": TestFixtures.makeKey(), "API_BASE_URL": ""]
        )
        #expect(throws: RailtownLoggerError.self) {
            try loader.apiBaseURL(in: bundle)
        }
    }
}
