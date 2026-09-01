//
//  ConductrTracePayloadMapperTests.swift
//  RailtownLoggerTests
//

import Foundation
import Testing
@testable import RailtownLogger

@Suite struct ConductrTracePayloadMapperTests {
    private let mapper = ConductrTracePayloadMapper()

    /// A trace file as the flow graph writes one.
    private var session: [String: Any] {
        [
            "session_id": "session-1",
            "flow_name": "Checkout flow",
            "start_time": 1_000,
            "end_time": 2_000,
            "runs": [
                [
                    "run_id": "run-1",
                    "name": "First run",
                    "start_time": 1_100,
                    "end_time": 1_900,
                    "status": "Completed",
                    "nodes": [["id": "n1"]],
                    "edges": [],
                    "steps": [["id": "s1"]],
                ],
                ["run_id": "run-2"],
            ],
        ]
    }

    @Test func flattensTheSessionAndItsFirstRun() throws {
        let body = try #require(
            JSONSerialization.jsonObject(with: mapper.bodyData(for: session)) as? [String: Any]
        )
        #expect(body["session_id"] as? String == "session-1")
        #expect(body["session_name"] as? String == "Checkout flow")
        #expect(body["session_start_time"] as? Int == 1_000)
        // The second run is dropped, not merged.
        #expect(body["run_id"] as? String == "run-1")
        #expect(body["run_status"] as? String == "Completed")
        #expect((body["nodes"] as? [[String: Any]])?.count == 1)
    }

    /// The server reads the body positionally in places, so key order is part of the contract.
    @Test func emitsKeysInTheServersOrder() throws {
        let json = try #require(String(data: mapper.bodyData(for: session), encoding: .utf8))
        let keys = json.split(separator: ",").compactMap { pair -> String? in
            guard let name = pair.split(separator: ":").first else { return nil }
            return name.trimmingCharacters(in: CharacterSet(charactersIn: "{\""))
        }
        #expect(
            keys.prefix(9) == [
                "session_id", "session_name", "session_start_time", "session_end_time",
                "run_id", "run_name", "run_start_time", "run_end_time", "run_status",
            ]
        )
    }

    @Test func fallsBackToNameThenIDForTheSessionName() throws {
        var withoutFlowName = session
        withoutFlowName["flow_name"] = nil
        withoutFlowName["name"] = "Fallback name"
        #expect(try sessionName(of: withoutFlowName) == "Fallback name")

        withoutFlowName["name"] = nil
        #expect(try sessionName(of: withoutFlowName) == "session-1")
    }

    /// A JSON `null` decodes to `NSNull`, which must not win over the next fallback.
    @Test func treatsAJSONNullNameAsAbsent() throws {
        var nulled = session
        nulled["flow_name"] = NSNull()
        #expect(try sessionName(of: nulled) == "session-1")
    }

    @Test func substitutesDefaultsForAMissingRun() throws {
        var runless = session
        runless["runs"] = []
        let body = try #require(
            JSONSerialization.jsonObject(with: mapper.bodyData(for: runless)) as? [String: Any]
        )
        #expect(body["session_id"] as? String == "session-1")
        #expect(body["run_status"] as? String == "Unknown")
        // Timestamps fall back to "now" rather than being omitted.
        #expect(body["run_start_time"] as? Int != nil)
        #expect(body["run_id"] == nil)
    }

    @Test func carriesUnrecognizedKeysAfterTheKnownOnes() throws {
        let data = try mapper.serializeOrdered(["custom": "value", "session_id": "session-1"])
        #expect(
            String(data: data, encoding: .utf8) == #"{"session_id":"session-1","custom":"value"}"#
        )
    }

    private func sessionName(of session: [String: Any]) throws -> String? {
        let body = try #require(
            JSONSerialization.jsonObject(with: mapper.bodyData(for: session)) as? [String: Any]
        )
        return body["session_name"] as? String
    }
}
