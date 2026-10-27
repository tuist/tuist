import Foundation
import Testing

struct AtlasActivityTests {
    @Test func decodesAPNsContentWithoutACustomJSONStrategy() throws {
        let data = Data("""
        {"active_count":5,"conversations":[
          {"id":"01922cc0-0000-7000-8000-000000000001","status":"using_tools",
           "started_at":1792923010,"completed_steps":7,"title":"Plan the Lisbon offsite"},
          {"id":"01922cc0-0000-7000-8000-000000000002","status":"compacting",
           "started_at":1792923000,"completed_steps":2}],"updated_at":1792923123}
        """.utf8)
        let state = try JSONDecoder().decode(AtlasActivityAttributes.ContentState.self, from: data)
        #expect(state.activeCount == 5)
        #expect(state.conversations.map(\.completedSteps) == [7, 2])
        #expect(state.conversations.map(\.status) == [.usingTools, .compacting])
        #expect(state.conversations.map(\.displayTitle) == ["Plan the Lisbon offsite", "Conversation"])
        #expect(state.startedAt == Date(timeIntervalSince1970: 1_792_923_000))
        #expect(!state.isEmpty)
        let encoded = try JSONEncoder().encode(state)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
        let original = try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
        #expect(object == original)
        let end = try JSONDecoder().decode(AtlasActivityAttributes.ContentState.self, from: Data(
            "{\"active_count\":0,\"conversations\":[],\"updated_at\":1792923140}".utf8
        ))
        #expect(end.isEmpty)
        #expect(end.startedAt == nil)
    }

    @Test func activityLinksReenterTheOriginBoundNativeRouter() throws {
        let server = try #require(URL(string: "https://atlas.example.org:4443/"))
        let attributes = AtlasActivityAttributes(registrationID: UUID().uuidString.lowercased(), server: server.absoluteString)
        let conversation = AtlasActivityAttributes.Conversation(
            id: "01922cc0-0000-7000-8000-000000000003", status: .queued, startedAt: 1_792_923_000, completedSteps: 0,
            title: "Review the launch checklist"
        )
        let link = try #require(attributes.destination(for: conversation))
        let destination = try #require(AtlasDestination(url: link))
        #expect(destination.screen == "orbit")
        #expect(destination.recordID == conversation.id)
        #expect(destination.matches(server))
        #expect(!destination.matches(URL(string: "https://atlas.example.org")!))
        #expect(!link.absoluteString.contains("Review"))
        let inboxLink = try #require(attributes.destination())
        let inbox = try #require(AtlasDestination(url: inboxLink))
        #expect(inbox.screen == "orbit")
        #expect(inbox.recordID == nil)
    }
}
