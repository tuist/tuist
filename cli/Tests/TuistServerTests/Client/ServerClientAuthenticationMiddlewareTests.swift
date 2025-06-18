import Foundation
import HTTPTypes
import Mockable
import OpenAPIRuntime
import Testing
import TuistSupport
import TuistTesting

@testable import TuistServer

struct ServerClientAuthenticationMiddlewareTests {
    private var subject: ServerClientAuthenticationMiddleware!
    private var serverAuthenticationController: MockServerAuthenticationControlling!

    init() {
        serverAuthenticationController = .init()
        subject = .init(serverAuthenticationController: serverAuthenticationController)
    }

    @Test func throws_when_theres_no_token() async throws {
        // Given
        let url = URL(string: "https://test.tuist.dev")!
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
        let response = HTTPResponse(
            status: 200
        )
        given(serverAuthenticationController).authenticationToken(serverURL: .value(url), forceRefresh: .value(false))
            .willReturn(nil)

        // When / Then
        await #expect(throws: ServerClientAuthenticationError.notAuthenticated, performing: {
            try await subject.intercept(
                request,
                body: nil,
                baseURL: url,
                operationID: "123"
            ) { _, _, _ in
                (response, nil)
            }
        })
    }

    @Test func uses_the_token_when_present() async throws {
        // Given
        let url = URL(string: "https://test.tuist.dev")!
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
        let response = HTTPResponse(
            status: 200
        )
        let token: AuthenticationToken? = .user(
            legacyToken: nil,
            accessToken: .test(token: "access-token"),
            refreshToken: .test(token: "refresh-token")
        )
        given(serverAuthenticationController).authenticationToken(serverURL: .value(url), forceRefresh: .value(false))
            .willReturn(token)
        var gotRequest: HTTPRequest!

        // When
        let (gotResponse, _) = try await subject.intercept(
            request,
            body: nil,
            baseURL: url,
            operationID: "123"
        ) { request, body, _ in
            gotRequest = request
            return (response, body)
        }

        // Then
        #expect(gotResponse == response)
        #expect(
            gotRequest.headerFields ==
                [
                    .authorization: "Bearer access-token",
                ]
        )
    }
}
