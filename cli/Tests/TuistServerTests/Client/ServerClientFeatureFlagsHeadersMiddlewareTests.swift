import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
import TuistEnvironment

@testable import TuistServer

struct ServerClientFeatureFlagsHeadersMiddlewareTests {
    @Test func adds_feature_flag_header() async throws {
        let environment = Environment(
            variables: [
                "TUIST_FEATURE_A": "1",
            ],
            arguments: []
        )
        let subject = ServerClientFeatureFlagsHeadersMiddleware()
        let url = URL(string: "https://tuist.dev")!
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
        let response = HTTPResponse(status: 200)
        var gotRequest: HTTPRequest?

        let (gotResponse, _) = try await Environment.$current.withValue(environment) {
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

        let featureFlagsHeaderName = try #require(HTTPField.Name(ClientFeatureFlags.headerName))
        #expect(gotResponse == response)
        #expect(gotRequest?.headerFields[featureFlagsHeaderName] == "A")
    }
}
