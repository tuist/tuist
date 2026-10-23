import Foundation
import SwiftUI

/// Fixture-only snapshots for rendering production thread views offline.
@MainActor
final class AtlasOrbitPreviewData: ObservableObject {
    private var sequence = 0
    private var selected: [String: Any]?
    private var draft = ""
    private let privateID = "01922cc0-0000-7000-8000-000000000001"
    private let sharedID = "01922cc0-0000-7000-8000-000000000002"

    func request(_ action: [String: Any]) async throws -> Data {
        if action["action"] as? String == "open" { return Data("{\"connection\":\"preview-only\"}".utf8) }
        let command = action["command"] as? [String: Any] ?? [:]
        switch command["action"] as? String {
        case "private": selected = thread(id: privateID, title: "Pip", kind: "private")
        case "select": selected = thread(id: sharedID, title: "Build listing latency", kind: "shared")
        case "create": selected = thread(id: sharedID, title: command["title"] as? String ?? "A new thread", kind: "shared")
        case "leave": selected = nil
        case "send": draft = ""
        default: break
        }
        return try snapshot()
    }

    func local(_ action: [String: Any]) async throws -> Data {
        if action["action"] as? String == "component_action" {
            return try JSONSerialization.data(withJSONObject: [
                "effect": "show_evidence", "thread_id": action["id"] as? String ?? "", "message_id": action["message_id"] as? String ?? ""
            ])
        }
        if action["action"] as? String == "next" { try await Task.sleep(for: .seconds(30)) }
        if action["action"] as? String == "draft" { draft = action["body"] as? String ?? "" }
        return try snapshot()
    }

    private func snapshot() throws -> Data {
        sequence += 1
        var messages: [[String: Any]] = []
        if selected != nil {
            messages = [
                message(id: "message-1", kind: "agent", body: "The build listing became slower after this morning’s deployment. I’m comparing the query plans."),
                message(id: "message-2", kind: "tool", body: "Compared query plans", extra: [
                    "tool_name": "Query plans", "tool_status": "succeeded", "tool_output": "The new filter bypasses the existing index.",
                    "component": ProcessInfo.processInfo.arguments.contains("--legacy-thread-cards") ? NSNull() : [
                        "type": "result_table", "version": 1,
                        "data": ["title": "Query comparison", "columns": ["Finding", "Impact"],
                                 "rows": [["The new filter bypasses the existing index.", "2.4× slower"]]],
                        "actions": [["id": "show_evidence", "label": "View source"]],
                        "fallback": "The new filter bypasses the existing index."
                    ] as Any
                ]),
                message(id: "message-3", kind: "human", body: "Check whether other projects are affected too.", extra: [
                    "author_id": "preview-self", "author_name": "Taylor"
                ])
            ]
            if selected?["kind"] as? String == "shared" {
                messages.insert(message(id: "message-alex", kind: "human", body: "I noticed it on the dashboard as well.", extra: [
                    "author_id": "online", "author_name": "Alex"
                ]), at: 0)
            }
        }
        return try JSONSerialization.data(withJSONObject: [
            "sequence": sequence, "assistant": ["name": "Pip", "configured": true],
            "threads": [thread(id: privateID, title: "Pip", kind: "private"),
                              thread(id: sharedID, title: "Build listing latency", kind: "shared")],
            "selected": selected as Any? ?? NSNull(), "messages": messages,
            "people": selected?["kind"] as? String == "shared" ? [["id": "online", "name": "Alex", "typing": false]] : [],
            "draft": draft, "loading": false, "history_loading": false, "saving": false,
            "has_more": false, "has_older": false, "needs_session": false
        ])
    }

    private func thread(id: String, title: String, kind: String) -> [String: Any] {
        ["id": id, "title": title, "kind": kind, "status": "Investigating", "summary": kind == "shared" ? "Comparing query plans across affected projects." : "",
         "origin": kind == "private" ? "manual" : "monitor", "participants": [["id": privateID, "name": "Alex"]],
         "updated_at": "2027-06-07T10:42:00Z"]
    }

    private func message(id: String, kind: String, body: String, extra: [String: Any] = [:]) -> [String: Any] {
        var value: [String: Any] = ["id": id, "kind": kind, "body": body, "author_name": "Pip", "inserted_at": "2027-06-07T10:42:00Z", "tool_input": "", "tool_output": ""]
        for (key, field) in extra { value[key] = field }
        return value
    }
}
