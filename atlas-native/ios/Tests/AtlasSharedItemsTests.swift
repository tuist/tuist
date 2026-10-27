import Foundation
import Testing

@MainActor
struct AtlasSharedItemsTests {
    @Test func restoresUnconfirmedPayloadAndRetriesTheSameCaptureAfterRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = AtlasShareInbox(directory: directory)
        let recipient = AtlasShareRecipient(id: UUID(), server: try #require(URL(string: "https://atlas.example")))
        try inbox.configure(recipient)
        try inbox.enqueue(url: "", content: "An original idea", recipient: recipient, title: "Reviewed", description: "My note")
        let original = try #require(inbox.captures(for: recipient).first)
        let first = AtlasSharedItems(inbox: inbox, recipient: recipient) { _ in
            throw AtlasAuthenticationError(kind: "unavailable", message: "Offline")
        }
        first.select(original)
        await first.save()
        #expect(first.errorMessage == "Offline")
        let uncertain = try #require(inbox.captures(for: recipient).first)
        #expect(uncertain.submitted && uncertain.id == original.id)
        #expect(uncertain.title == "Reviewed" && uncertain.description == "My note")
        let restored = AtlasSharedItems(inbox: inbox, recipient: recipient) { action in
            #expect(action["request_id"] as? String == original.id.uuidString.lowercased())
            let attributes = try #require(action["attributes"] as? [String: Any])
            #expect(NSDictionary(dictionary: attributes).isEqual(to: original.attributes))
            return Data("{\"saved\":true,\"resource_id\":\"\(UUID().uuidString)\"}".utf8)
        }
        restored.select(uncertain)
        await restored.save()
        #expect(try inbox.captures(for: recipient).isEmpty)
        #expect(restored.draft == nil && restored.errorMessage == nil)
    }

    @Test func recipientChangesPurgeOldSharesAndRejectStaleWriters() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = AtlasShareInbox(directory: directory)
        let server = try #require(URL(string: "https://atlas.example"))
        let first = AtlasShareRecipient(id: UUID(), server: server)
        let second = AtlasShareRecipient(id: UUID(), server: server)
        try inbox.configure(first)
        try inbox.enqueue(url: "https://example.com/reference", content: "", recipient: first)
        let capture = try #require(inbox.captures(for: first).first)
        try inbox.configure(second)
        #expect(try inbox.captures(for: second).isEmpty)
        #expect(throws: (any Error).self) { try inbox.save(capture) }
        #expect(throws: (any Error).self) { try inbox.enqueue(url: "", content: "Old share sheet", recipient: first) }
        try inbox.configure(nil)
        #expect(throws: (any Error).self) { try inbox.enqueue(url: "", content: "Signed out", recipient: second) }
    }

    @Test func inferencePreservesTypingAndUserNotesWhileFillingUntouchedFields() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = AtlasShareInbox(directory: directory)
        let recipient = AtlasShareRecipient(id: UUID(), server: try #require(URL(string: "https://atlas.example")))
        try inbox.configure(recipient)
        try inbox.enqueue(url: "", content: "Original text", recipient: recipient, description: "My note")
        var model: AtlasSharedItems!
        model = AtlasSharedItems(inbox: inbox, recipient: recipient) { _ in
            model.draft?.title = "Typed while inference ran"
            return Data("""
            {"suggestions":{"title":"AI title","description":"AI summary","tags":["design"],"generated":true}}
            """.utf8)
        }
        model.select(try #require(inbox.captures(for: recipient).first))
        await model.suggest()
        #expect(model.draft?.title == "Typed while inference ran")
        #expect(model.draft?.description == "My note")
        #expect(model.draft?.tags == ["design"])
        #expect(try inbox.captures(for: recipient).first?.title == "Typed while inference ran")

        let reopened = AtlasSharedItems(inbox: inbox, recipient: recipient) { _ in
            Data("""
            {"suggestions":{"title":"Replacement","description":"Replacement","tags":["other"],"generated":true}}
            """.utf8)
        }
        reopened.select(try #require(inbox.captures(for: recipient).first))
        await reopened.suggest()
        #expect(reopened.draft?.title == "Typed while inference ran")
        #expect(reopened.draft?.description == "My note")
        #expect(reopened.draft?.tags == ["design"])
    }
}
