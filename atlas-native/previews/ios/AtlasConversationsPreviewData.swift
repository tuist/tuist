import Foundation
import SwiftUI

/// Fixture-only snapshots for rendering production conversation views offline.
@MainActor
final class AtlasConversationsPreviewData: ObservableObject {
    private var sequence = 0
    private var selected: [String: Any]?
    private var draft = ""
    private let privateID = "01922cc0-0000-7000-8000-000000000001"
    private let sharedID = "01922cc0-0000-7000-8000-000000000002"

    func request(_ action: [String: Any]) async throws -> Data {
        if action["action"] as? String == "open" { return Data("{\"connection\":\"preview-only\"}".utf8) }
        let command = action["command"] as? [String: Any] ?? [:]
        switch command["action"] as? String {
        case "private": selected = conversation(id: privateID, title: "Juniper", kind: "private")
        case "select": selected = conversation(id: sharedID, title: "Build listing latency", kind: "shared")
        case "create": selected = conversation(id: sharedID, title: command["title"] as? String ?? "A new conversation", kind: "shared")
        case "leave": selected = nil
        case "send": draft = ""
        default: break
        }
        return try snapshot()
    }

    func local(_ action: [String: Any]) async throws -> Data {
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
                    "tool_name": "Query plans", "tool_status": "completed", "tool_output": "The new filter bypasses the existing index."
                ]),
                message(id: "message-3", kind: "human", body: "Check whether other projects are affected too.", extra: ["author_name": "Alex"])
            ]
        }
        return try JSONSerialization.data(withJSONObject: [
            "sequence": sequence, "bot": ["name": "Juniper", "configured": true],
            "conversations": [conversation(id: privateID, title: "Juniper", kind: "private"),
                              conversation(id: sharedID, title: "Build listing latency", kind: "shared")],
            "selected": selected as Any? ?? NSNull(), "messages": messages,
            "people": selected == nil ? [] : [["id": privateID, "name": "Alex", "typing": false]],
            "draft": draft, "loading": false, "history_loading": false, "saving": false,
            "has_more": false, "has_older": false, "needs_session": false
        ])
    }

    private func conversation(id: String, title: String, kind: String) -> [String: Any] {
        ["id": id, "title": title, "kind": kind, "status": "Investigating", "summary": kind == "shared" ? "Comparing query plans across affected projects." : "",
         "origin": kind == "private" ? "manual" : "monitor", "participants": [["id": privateID, "name": "Alex"]],
         "updated_at": "2027-06-07T10:42:00Z"]
    }

    private func message(id: String, kind: String, body: String, extra: [String: Any] = [:]) -> [String: Any] {
        var value: [String: Any] = ["id": id, "kind": kind, "body": body, "author_name": "Juniper", "inserted_at": "2027-06-07T10:42:00Z", "tool_input": "", "tool_output": ""]
        for (key, field) in extra { value[key] = field }
        return value
    }
}
