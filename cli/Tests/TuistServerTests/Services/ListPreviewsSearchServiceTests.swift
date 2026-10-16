import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
import TuistHTTP

@testable import TuistServer

struct ListPreviewsSearchServiceTests {
    private let serverURL = URL(string: "https://self-hosted.example.com")!

    private func subject(search: String?, page: Int) -> ListPreviewsService {
        ListPreviewsService(fullHandleService: FullHandleService(), makeClient: { url in
            Client(serverURL: url, transport: PreviewsSearchTransport(expectedSearch: search, expectedPage: page))
        })
    }

    @Test(arguments: ["BLUE", "100%_ready", "iOS & Android"])
    func search_preserves_literal_text_and_combines_with_track_and_pagination(search: String) async throws {
        let result = try await subject(search: search, page: 2).searchPreviews(
            search: search, track: "QA", page: 2, pageSize: 20, fullHandle: "team/app", serverURL: serverURL
        )
        #expect(result.previews.isEmpty)
    }

    @Test func existing_listing_requests_do_not_send_a_search_parameter() async throws {
        let result = try await subject(search: nil, page: 1).listPreviews(
            displayName: nil, specifier: nil, track: "QA", supportedPlatforms: [],
            page: 1, pageSize: 20, distinctField: nil, fullHandle: "team/app", serverURL: serverURL
        )
        #expect(result.previews.isEmpty)
    }
}

private struct PreviewsSearchTransport: ClientTransport {
    let expectedSearch: String?
    let expectedPage: Int

    func send(
        _ request: HTTPRequest,
        body _: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        #expect(baseURL.absoluteString == "https://self-hosted.example.com")
        #expect(request.method == .get)
        #expect(operationID == "listPreviews")
        let url = try #require(URLComponents(string: baseURL.absoluteString + (request.path ?? "")))
        #expect(url.path == "/api/projects/team/app/previews")
        let items = url.queryItems ?? []
        #expect(items.first(where: { $0.name == "search" })?.value == expectedSearch)
        #expect(items.first(where: { $0.name == "track" })?.value == "QA")
        #expect(items.first(where: { $0.name == "page" })?.value == String(expectedPage))
        #expect(items.first(where: { $0.name == "page_size" })?.value == "20")
        var response = HTTPResponse(status: .ok)
        response.headerFields[.contentType] = "application/json"
        return (
            response,
            HTTPBody(
                #"{"previews":[],"pagination_metadata":{"has_next_page":false,"has_previous_page":false,"current_page":1,"page_size":20,"total_count":0,"total_pages":0}}"#
            )
        )
    }
}
