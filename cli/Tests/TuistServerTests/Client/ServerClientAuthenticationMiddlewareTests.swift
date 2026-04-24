import Foundation
import HTTPTypes
import Mockable
import OpenAPIRuntime
import Testing
import TuistHTTP
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
        given(serverAuthenticationController).authenticationToken(
            serverURL: .value(url),
            refreshIfNeeded: .value(true)
        )
        .willReturn(nil)

        // When / Then
        await #expect(throws: ClientAuthenticationError.notAuthenticated, performing: {
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
            accessToken: .test(token: "access-token"),
            refreshToken: .test(token: "refresh-token")
        )
        given(serverAuthenticationController).authenticationToken(
            serverURL: .value(url),
            refreshIfNeeded: .value(true)
        )
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

    @Test func uses_custom_authentication_url_when_provided() async throws {
        // Given
        let baseURL = URL(string: "https://cache.tuist.dev")!
        let authenticationURL = URL(string: "https://api.tuist.dev")!
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
        let response = HTTPResponse(
            status: 200
        )
        let token: AuthenticationToken? = .user(
            accessToken: .test(token: "auth-token"),
            refreshToken: .test(token: "refresh-token")
        )

        let customSubject = ServerClientAuthenticationMiddleware(
            serverAuthenticationController: serverAuthenticationController,
            authenticationURL: authenticationURL
        )

        given(serverAuthenticationController).authenticationToken(
            serverURL: .value(authenticationURL),
            refreshIfNeeded: .value(true)
        )
        .willReturn(token)
        var gotRequest: HTTPRequest!

        // When
        let (gotResponse, _) = try await customSubject.intercept(
            request,
            body: nil,
            baseURL: baseURL,
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
                    .authorization: "Bearer auth-token",
                ]
        )

        // Verify authentication was requested with the custom URL, not the baseURL
        verify(serverAuthenticationController)
            .authenticationToken(
                serverURL: .value(authenticationURL),
                refreshIfNeeded: .value(true)
            )
            .called(1)
    }

    @Test func uses_base_url_when_no_custom_authentication_url() async throws {
        // Given
        let baseURL = URL(string: "https://api.tuist.dev")!
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
        let response = HTTPResponse(
            status: 200
        )
        let token: AuthenticationToken? = .user(
            accessToken: .test(token: "base-token"),
            refreshToken: .test(token: "refresh-token")
        )

        let defaultSubject = ServerClientAuthenticationMiddleware(
            serverAuthenticationController: serverAuthenticationController,
            authenticationURL: nil
        )

        given(serverAuthenticationController).authenticationToken(
            serverURL: .value(baseURL),
            refreshIfNeeded: .value(true)
        )
        .willReturn(token)
        var gotRequest: HTTPRequest!

        // When
        let (gotResponse, _) = try await defaultSubject.intercept(
            request,
            body: nil,
            baseURL: baseURL,
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
                    .authorization: "Bearer base-token",
                ]
        )

        // Verify authentication was requested with the baseURL
        verify(serverAuthenticationController)
            .authenticationToken(
                serverURL: .value(baseURL),
                refreshIfNeeded: .value(true)
            )
            .called(1)
    }

    @Test func allows_requests_without_a_token_when_optional_authentication_is_enabled() async throws {
        // Given
        let url = URL(string: "https://test.tuist.dev")!
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
        let response = HTTPResponse(status: 200)
        given(serverAuthenticationController).authenticationToken(
            serverURL: .value(url),
            refreshIfNeeded: .value(false)
        )
        .willReturn(nil)
        var gotRequest: HTTPRequest!

        // When
        let (gotResponse, _) = try await ServerAuthenticationConfig.$current.withValue(
            .init(optionalAuthentication: true)
        ) {
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

        // Then
        #expect(gotResponse == response)
        #expect(gotRequest.headerFields == request.headerFields)
    }
}
