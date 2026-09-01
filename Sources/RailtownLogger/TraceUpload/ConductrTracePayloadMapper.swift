//
//  ConductrTracePayloadMapper.swift
//  RailtownLogger
//

import Foundation

/// Translates a flow-graph trace file into the JSON body the Conductr server expects; mirrors
/// RailtownAI/handler.py.
///
/// Split out of ``ConductrTraceUploader`` because the two answer to different things: the uploader
/// tracks Azure's blob API, while this tracks the server's trace schema. Only ``bodyData(for:)``
/// is called from outside; the two steps below it are separate so each can be exercised on its own.
///
/// Works in untyped `[String: Any]` rather than `Codable` models deliberately — `nodes`, `edges`,
/// and `steps` are passed through to the server verbatim, and decoding them into Swift types would
/// mean re-encoding them, which risks changing a payload this SDK does not own.
struct ConductrTracePayloadMapper: Sendable {

    /// Flattens `session` and its first run into the wire body.
    ///
    /// A trace file holds a `runs` array; only the first is uploaded, and a file with none still
    /// produces a session-only body rather than failing.
    func bodyData(for session: [String: Any]) throws -> Data {
        let run = (session["runs"] as? [[String: Any]])?.first ?? [:]
        return try serializeOrdered(enrichRunWithSession(session, run: run))
    }

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
    ///
    /// - Throws: ``RailtownLoggerError/invalidTracePayload(reason:)`` if the assembled JSON is not
    ///   valid UTF-8, or `JSONSerialization`'s own error when a value cannot be encoded at all.
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
                throw RailtownLoggerError.invalidTracePayload(
                    reason: "The JSON encoded for key \"\(key)\" is not valid UTF-8."
                )
            }
            jsonString += "\"\(key)\":\(String(wrappedString.dropFirst().dropLast()))"
            if index < orderedPairs.count - 1 {
                jsonString += ","
            }
        }
        jsonString += "}"
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw RailtownLoggerError.invalidTracePayload(
                reason: "The assembled trace body is not valid UTF-8."
            )
        }
        return jsonData
    }
}
