import Foundation
import Testing
import TuistServer

@testable import TuistPreviews

struct PreviewNavigationTests {
    @Test func shared_preview_links_keep_their_own_project_scope() throws {
        let url = try #require(URL(string: "https://tuist.dev/public/example/previews/shared-preview"))

        let preview = try #require(DeeplinkPreview(url: url))

        #expect(preview.fullHandle == "public/example")
        #expect(preview.previewId == "shared-preview")
    }

    @Test(arguments: [
        "tuist://oauth-callback?code=example",
        "https://tuist.dev/public/example",
        "https://tuist.dev/public/example/previews",
        "https://tuist.dev/public/example/builds/build-id",
    ])
    func unrelated_urls_are_not_preview_destinations(url: String) throws {
        #expect(DeeplinkPreview(url: try #require(URL(string: url))) == nil)
    }

    @Test func destination_identity_includes_the_project() {
        let preview = ServerPreview.test(id: "shared-id")
        let first = PreviewDestination(preview: preview, fullHandle: "tuist/first")
        let second = PreviewDestination(preview: preview, fullHandle: "tuist/second")

        #expect(first != second)
    }
}
