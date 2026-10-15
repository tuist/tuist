import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
import TuistHTTP

@testable import TuistServer

struct ListPreviewTracksServiceTests {
    private let serverURL = URL(string: "https://self-hosted.example.com")!

    private func subject(status: Int, json: String) -> ListPreviewTracksService {
        ListPreviewTracksService(makeClient: { url in
            Client(serverURL: url, transport: TracksTransport(status: status, json: json))
        })
    }

    @Test(arguments: [[String](), ["QA", "Release/2027 β"]])
    func accepts_empty_lists_and_open_track_names(tracks: [String]) async throws {
        let json = String(decoding: try JSONEncoder().encode(tracks), as: UTF8.self)
        let result = try await subject(status: 200, json: json).listPreviewTracks(fullHandle: "team/app", serverURL: serverURL)
        #expect(result == tracks)
    }

    @Test func older_servers_without_the_endpoint_return_no_track_discovery() async throws {
        let result = try await subject(status: 404, json: "<html>Not found</html>")
            .listPreviewTracks(fullHandle: "team/app", serverURL: serverURL)
        #expect(result == nil)
    }

    @Test(arguments: [401, 403])
    func authorization_failures_are_not_mistaken_for_legacy_servers(status: Int) async throws {
        let error: ListPreviewsServiceError = status == 401 ? .unauthorized("denied") : .forbidden("denied")
        await #expect(throws: error) {
            try await subject(status: status, json: #"{"message":"denied"}"#)
                .listPreviewTracks(fullHandle: "team/app", serverURL: serverURL)
        }
    }

    @Test func rate_limits_preserve_retry_after() async throws {
        await #expect(throws: AuthorizationThrottledError(retryAfterSeconds: 7)) {
            try await subject(status: 429, json: #"{"message":"slow down"}"#)
                .listPreviewTracks(fullHandle: "team/app", serverURL: serverURL)
        }
    }

    @Test func server_failures_remain_errors() async throws {
        await #expect(throws: ListPreviewsServiceError.unknownError(500)) {
            try await subject(status: 500, json: #"{"message":"unavailable"}"#)
                .listPreviewTracks(fullHandle: "team/app", serverURL: serverURL)
        }
    }
}

private struct TracksTransport: ClientTransport {
    let status: Int
    let json: String

    func send(
        _ request: HTTPRequest,
        body _: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        #expect(baseURL.absoluteString == "https://self-hosted.example.com")
        #expect(request.method == .get)
        #expect(request.path == "/api/projects/team/app/previews/tracks")
        #expect(operationID == "listPreviewTracks")
        var response = HTTPResponse(status: .init(code: status))
        response.headerFields[.contentType] = "application/json"
        response.headerFields[.retryAfter] = "7"
        return (response, HTTPBody(json))
    }
}
