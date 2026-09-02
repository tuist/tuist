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
                "TUIST_FEATURE_FLAG_A": "1",
            ],
            arguments: []
        )

        let headerValue = try await headerValue(environment: environment)

        #expect(headerValue == "A,KURA")
    }

    @Test func adds_the_default_enabled_feature_flags_when_no_variable_is_set() async throws {
        let environment = Environment(variables: [:], arguments: [])

        let headerValue = try await headerValue(environment: environment)

        #expect(headerValue == "KURA")
    }

    @Test func omits_a_feature_flag_disabled_by_a_falsey_value() async throws {
        let environment = Environment(
            variables: [
                "TUIST_FEATURE_FLAG_KURA": "0",
                "TUIST_FEATURE_FLAG_A": "1",
            ],
            arguments: []
        )

        let headerValue = try await headerValue(environment: environment)

        #expect(headerValue == "A")
    }

    @Test func omits_the_header_when_every_feature_flag_is_disabled() async throws {
        let environment = Environment(
            variables: [
                "TUIST_FEATURE_FLAG_KURA": "false",
            ],
            arguments: []
        )

        let headerValue = try await headerValue(environment: environment)

        #expect(headerValue == nil)
    }

    private func headerValue(environment: Environment) async throws -> String? {
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
        return gotRequest?.headerFields[featureFlagsHeaderName]
    }
}
