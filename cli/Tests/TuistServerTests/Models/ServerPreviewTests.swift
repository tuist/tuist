import Foundation
import Testing

@testable import TuistServer

@Suite struct ServerPreviewTests {
    @Test func preserves_track_and_release_notes() throws {
        var response = Components.Schemas.Preview.test(track: "QA")
        response.release_notes = "Fix sign-in\nReady for testing"

        let preview = try ServerPreview(response)

        #expect(preview.track == "QA")
        #expect(preview.releaseNotes == "Fix sign-in\nReady for testing")
    }

    @Test func accepts_older_server_responses_without_track_or_notes() throws {
        let data = Data("""
        {"id":"legacy","url":"https://example.com/preview","qr_code_url":"https://example.com/qr.png",
         "icon_url":"https://example.com/icon.png","device_url":"https://example.com/install",
         "inserted_at":"2024-01-01T00:00:00Z","builds":[],"supported_platforms":[],"created_from_ci":false}
        """.utf8)
        let response = try JSONDecoder().decode(Components.Schemas.Preview.self, from: data)

        let preview = try ServerPreview(response)

        #expect(preview.track == nil)
        #expect(preview.releaseNotes == nil)
    }

    @Test func ignores_unknown_fields_from_future_servers_and_accepts_new_track_names() throws {
        let data = Data("""
        {"id":"future","url":"https://example.com/preview","qr_code_url":"https://example.com/qr.png",
         "icon_url":"https://example.com/icon.png","device_url":"https://example.com/install",
         "inserted_at":"2024-01-01T00:00:00Z","builds":[],"supported_platforms":[],"created_from_ci":false,
         "track":"future-track-2030","release_notes":"Still plain text",
         "future_metadata":{"title":"An additive field","labels":["internal"]}}
        """.utf8)
        let response = try JSONDecoder().decode(Components.Schemas.Preview.self, from: data)
        let preview = try ServerPreview(response)

        #expect(preview.track == "future-track-2030")
        #expect(preview.releaseNotes == "Still plain text")
    }
}
