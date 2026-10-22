import Foundation
import Testing

@MainActor
struct AtlasConversationsTests {
    private let id = "01922cc0-0000-7000-8000-000000000001"

    @Test func adapterForwardsCommandsAndRendersRustState() async throws {
        var commands: [String] = []
        let model = AtlasConversations(request: { action in
            if action["action"] as? String == "open" { return Data("{\"connection\":\"local-handle\"}".utf8) }
            #expect(action["connection"] as? String == "local-handle")
            let command = try #require(action["command"] as? [String: Any])
            let name = try #require(command["action"] as? String)
            commands.append(name)
            return try snapshot(sequence: commands.count, selected: name == "private")
        }, localRequest: { _ in throw CancellationError() })
        await model.load()
        #expect(model.bot?.name == "Juniper")
        #expect(model.hasMore)
        #expect(model.conversations.first?.id == id)
        let conversation = try #require(await model.privateConversation())
        await model.open(conversation)
        #expect(commands == ["load", "private"])
        #expect(model.selected?.id == id)
    }

    @Test func sendWaitsForDraftBridgeAndDoesNotReimplementIdempotency() async throws {
        var commands: [String] = []
        var draftSaved = false
        let model = AtlasConversations(request: { action in
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
        _ = await model.privateConversation()
        model.draft = "A thought"
        await model.send(addressAgent: true)
        #expect(commands == ["private", "send"])
        #expect(model.draft.isEmpty)
    }

    @Test func serverFailureKeepsTheFeatureAvailableForRetry() async {
        var fail = true
        let model = AtlasConversations(request: { action in
            if action["action"] as? String == "open" { return Data("{\"connection\":\"local-handle\"}".utf8) }
            if fail { throw AtlasAuthenticationError(kind: "server", message: "Try again later.") }
            return try snapshot(sequence: 1)
        }, localRequest: { _ in throw CancellationError() })
        await model.load()
        #expect(model.errorMessage == "Try again later.")
        fail = false
        await model.load()
        #expect(model.errorMessage == nil)
        #expect(model.bot?.name == "Juniper")
    }

    private func snapshot(sequence: Int, selected: Bool = false, draft: String = "") throws -> Data {
        let conversation: [String: Any] = [
            "id": id, "title": "Private conversation", "kind": "private", "status": "idle",
            "summary": "", "origin": "manual", "participants": [], "updated_at": "2027-06-07T10:00:00Z"
        ]
        return try JSONSerialization.data(withJSONObject: [
            "sequence": sequence, "bot": ["name": "Juniper", "configured": true],
            "conversations": [conversation], "selected": selected ? conversation as Any : NSNull(),
            "messages": [], "people": [], "draft": draft, "loading": false, "history_loading": false, "saving": false,
            "has_more": true, "has_older": false, "needs_session": false
        ])
    }
}
