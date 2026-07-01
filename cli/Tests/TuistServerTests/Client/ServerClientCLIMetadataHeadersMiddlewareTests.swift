import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
import TuistConstants

@testable import TuistServer

struct ServerClientCLIMetadataHeadersMiddlewareTests {
    @Test func sends_released_cli_version() async throws {
        let subject = ServerClientCLIMetadataHeadersMiddleware()
        let url = URL(string: "https://tuist.dev")!
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
        let response = HTTPResponse(status: 200)
        var gotRequest: HTTPRequest?

        let (gotResponse, _) = try await Constants.$version.withValue("4.201.0") {
            try await subject.intercept(
                request,
                body: nil,
                baseURL: url,
                operationID: "123"
            ) { request, body, _ in
                gotRequest = request
                return (response, body)
            }
        }

        let cliVersionHeaderName = try #require(HTTPField.Name("x-tuist-cli-version"))
        #expect(gotResponse == response)
        #expect(gotRequest?.headerFields[cliVersionHeaderName] == "4.201.0")
    }
}
