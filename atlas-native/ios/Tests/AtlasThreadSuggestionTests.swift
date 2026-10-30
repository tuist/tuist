import Foundation
import Testing

struct AtlasThreadSuggestionTests {
    @Test func followUpsBelongOnlyToTheLatestCompletedConversationTurn() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let values: [[String: Any]] = [
            ["id": "first", "kind": "agent", "body": "Accounts found.", "suggestions": ["Show account activity"]],
            ["id": "human", "kind": "human", "body": "Compare their tasks."],
            ["id": "second", "kind": "agent", "body": "Tasks compared.", "suggestions": ["Explain the priority"]]
        ]
        let messages = try values.map { value in
            let fields = value.merging(["author_name": "Pip", "inserted_at": "2026-10-29T12:00:00Z",
                                        "tool_input": "", "tool_output": ""]) { original, _ in original }
            return try decoder.decode(AtlasThreadMessage.self, from: JSONSerialization.data(withJSONObject: fields))
        }
        #expect(AtlasThreadSuggestion.prompts(messages: [messages[0]], welcome: false, agentStatus: "idle").map(\.text)
            == ["Show account activity"])
        #expect(AtlasThreadSuggestion.prompts(messages: Array(messages.prefix(2)), welcome: false, agentStatus: "idle").isEmpty)
        #expect(AtlasThreadSuggestion.prompts(messages: messages, welcome: false, agentStatus: "idle").map(\.text)
            == ["Explain the priority"])
        for status in ["queued", "running", "compacting"] {
            #expect(AtlasThreadSuggestion.prompts(messages: messages, welcome: false, agentStatus: status).isEmpty)
        }
        var legacy = messages[2]
        legacy.suggestions = nil
        #expect(AtlasThreadSuggestion.prompts(messages: [messages[0], legacy], welcome: false, agentStatus: "idle").isEmpty)
        #expect(AtlasThreadSuggestion.prompts(messages: [], welcome: false, agentStatus: nil).isEmpty)
        #expect(AtlasThreadSuggestion.prompts(messages: [], welcome: true, agentStatus: nil).map(\.text)
            == ["What needs my attention?", "Summarize my open tasks", "Find an account"])
    }
}
