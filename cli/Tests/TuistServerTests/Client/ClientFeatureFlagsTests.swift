import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
import TuistEnvironment

@testable import TuistServer

struct ClientFeatureFlagsTests {
    @Test func header_value_is_nil_when_no_feature_flags_are_present() async {
        let environment = Environment(
            variables: [
                "TUIST_TOKEN": "token",
                "CI": "true",
            ],
            arguments: []
        )

        let headerValue = await Environment.$current.withValue(environment) {
            ClientFeatureFlags.headerValue()
        }

        #expect(headerValue == nil)
    }

    @Test func header_value_encodes_feature_flags_as_a_comma_separated_list() async {
        let environment = Environment(
            variables: [
                "TUIST_FEATURE_B": "enabled",
                "TUIST_FEATURE_A": "1",
                "TUIST_TOKEN": "token",
            ],
            arguments: []
        )

        let headerValue = await Environment.$current.withValue(environment) {
            ClientFeatureFlags.headerValue()
        }

        #expect(headerValue == "A,B")
    }

    @Test func middleware_adds_feature_flag_header() async throws {
        let environment = Environment(
            variables: [
                "TUIST_FEATURE_A": "1",
            ],
            arguments: []
        )
        let middleware = ServerClientFeatureFlagsHeadersMiddleware()
        let url = URL(string: "https://tuist.dev")!
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
        let response = HTTPResponse(status: 200)
        var gotRequest: HTTPRequest?

        let (gotResponse, _) = try await Environment.$current.withValue(environment) {
            try await middleware.intercept(
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
