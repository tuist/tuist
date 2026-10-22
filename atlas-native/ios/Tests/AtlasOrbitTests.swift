import Foundation
import Testing

@MainActor
struct AtlasOrbitTests {
    private let id = "01922cc0-0000-7000-8000-000000000001"

    @Test func adapterForwardsCommandsAndRendersRustState() async throws {
        var commands: [String] = []
        let model = AtlasOrbit(request: { action in
            if action["action"] as? String == "open" { return Data("{\"connection\":\"local-handle\"}".utf8) }
            #expect(action["connection"] as? String == "local-handle")
            let command = try #require(action["command"] as? [String: Any])
            let name = try #require(command["action"] as? String)
            commands.append(name)
            return try snapshot(sequence: commands.count, selected: name == "private")
        }, localRequest: { _ in throw CancellationError() })
        await model.load()
        #expect(model.assistant?.name == "Juniper")
        #expect(model.hasMore)
        #expect(model.threads.first?.id == id)
        let thread = try #require(await model.privateThread())
        await model.open(thread)
        #expect(commands == ["load", "private"])
        #expect(model.selected?.id == id)
    }

    @Test func sendWaitsForDraftBridgeAndDoesNotReimplementIdempotency() async throws {
        var commands: [String] = []
        var draftSaved = false
        let model = AtlasOrbit(request: { action in
            if action["action"] as? String == "open" { return Data("{\"connection\":\"local-handle\"}".utf8) }
            let command = try #require(action["command"] as? [String: Any])
            let name = try #require(command["action"] as? String)
            commands.append(name)
            if name == "send" {
                #expect(draftSaved)
                #expect(command["address_agent"] as? Bool == true)
                #expect(command["id"] as? String == id)
                #expect(command["body"] as? String == "A thought")
                #expect(command["client_id"] == nil)
            }
            return try snapshot(sequence: name == "send" ? 3 : 1, selected: true)
        }, localRequest: { action in
            if action["action"] as? String == "close" { return Data("{}".utf8) }
            #expect(action["action"] as? String == "draft")
            #expect(action["id"] as? String == id)
            #expect(action["body"] as? String == "A thought")
            draftSaved = true
            return try snapshot(sequence: 2, selected: true, draft: "A thought")
        })
        _ = await model.privateThread()
        model.draft = "A thought"
        await model.send(addressAgent: true)
        #expect(commands == ["private", "send"])
        #expect(model.draft.isEmpty)
    }

    @Test func serverFailureKeepsTheFeatureAvailableForRetry() async {
        var fail = true
        let model = AtlasOrbit(request: { action in
            if action["action"] as? String == "open" { return Data("{\"connection\":\"local-handle\"}".utf8) }
            if fail { throw AtlasAuthenticationError(kind: "server", message: "Try again later.") }
            return try snapshot(sequence: 1)
        }, localRequest: { _ in throw CancellationError() })
        await model.load()
        #expect(model.errorMessage == "Try again later.")
        fail = false
        await model.load()
        #expect(model.errorMessage == nil)
        #expect(model.assistant?.name == "Juniper")
    }

    @Test func cardActionForwardsToRustAndRejectsLateEffectsAfterAccessLoss() async throws {
        var revoked = false
        var sequence = 0
        var delayed = false
        var pending: CheckedContinuation<Data, Error>?
        let message: [String: Any] = [
            "id": "evidence", "kind": "tool", "body": "", "author_name": "Juniper", "inserted_at": "2026-10-22T12:00:00Z",
            "tool_status": "succeeded", "tool_input": "", "tool_output": "original evidence",
            "component": ["type": "result_table", "version": 1, "data": ["title": "Accounts", "columns": ["Name"], "rows": [["Northstar"]]],
                          "actions": [["id": "show_evidence", "label": "View source"]], "fallback": "Northstar"]
        ]
        let effect = Data("{\"effect\":\"show_evidence\",\"thread_id\":\"\(id)\",\"message_id\":\"evidence\"}".utf8)
        let model = AtlasOrbit(request: { action in
            if action["action"] as? String == "open" { return Data("{\"connection\":\"handle\"}".utf8) }
            sequence += 1
            return try snapshot(sequence: sequence, selected: !revoked, messages: revoked ? [] : [message])
        }, localRequest: { action in
            if action["action"] as? String == "close" { return Data("{}".utf8) }
            #expect(action["action"] as? String == "component_action")
            #expect(action["connection"] as? String == "handle")
            #expect(action["id"] as? String == id)
            #expect(action["message_id"] as? String == "evidence")
            #expect(action["event"] as? String == "show_evidence")
            if delayed { return try await withCheckedThrowingContinuation { pending = $0 } }
            return effect
        })
        await model.load()
        #expect(model.messages.first?.component?.data.rows == [["Northstar"]])
        #expect(await model.componentAction(messageId: "evidence", event: "show_evidence"))
        delayed = true
        let action = Task { await model.componentAction(messageId: "evidence", event: "show_evidence") }
        while pending == nil { await Task.yield() }
        revoked = true
        await model.load()
        pending?.resume(returning: effect)
        #expect(await action.value == false)
        #expect(model.messages.isEmpty)
    }

    private func snapshot(sequence: Int, selected: Bool = false, draft: String = "", messages: [[String: Any]] = []) throws -> Data {
        let thread: [String: Any] = [
            "id": id, "title": "Private thread", "kind": "private", "status": "idle",
            "summary": "", "origin": "manual", "participants": [], "updated_at": "2027-06-07T10:00:00Z"
        ]
        return try JSONSerialization.data(withJSONObject: [
            "sequence": sequence, "assistant": ["name": "Juniper", "configured": true],
            "threads": [thread], "selected": selected ? thread as Any : NSNull(),
            "messages": messages, "people": [], "draft": draft, "loading": false, "history_loading": false, "saving": false,
            "has_more": true, "has_older": false, "needs_session": false
        ])
    }
}
