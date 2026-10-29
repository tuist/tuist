import Foundation
import HTTPTypes
import Mockable
import OpenAPIRuntime
import Synchronization
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
            refreshIfNeeded: .value(true)
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

    @Test func refreshes_expired_tokens_when_optional_authentication_is_enabled() async throws {
        // Regression: with `optionalAuthentication`, the middleware used to skip
        // the refresh path entirely, so an expired access token would silently
        // become "no auth header" until the user manually ran `tuist auth login`.
        // Now refresh is always attempted; falling through to unauthenticated is
        // reserved for the case where refresh actually fails.
        let url = URL(string: "https://test.tuist.dev")!
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
        let response = HTTPResponse(status: 200)
        let token: AuthenticationToken? = .user(
            accessToken: .test(token: "refreshed-access-token"),
            refreshToken: .test(token: "refresh-token")
        )
        given(serverAuthenticationController).authenticationToken(
            serverURL: .value(url),
            refreshIfNeeded: .value(true)
        )
        .willReturn(token)
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
        #expect(
            gotRequest.headerFields ==
                [
                    .authorization: "Bearer refreshed-access-token",
                ]
        )
    }

    @Test func swallows_refresh_errors_when_optional_authentication_is_enabled() async throws {
        // When the refresh attempt itself throws (network failure, refresh token
        // revoked, credentials wiped after a 401), an `optionalAuthentication`
        // call site should fall through to the unauthenticated path rather than
        // surface a hard failure to the caller.
        let url = URL(string: "https://test.tuist.dev")!
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
        let response = HTTPResponse(status: 200)
        given(serverAuthenticationController).authenticationToken(
            serverURL: .value(url),
            refreshIfNeeded: .value(true)
        )
        .willThrow(RefreshAuthTokenServiceError.unauthorized("Invalid token"))
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

    @Test func propagates_refresh_errors_when_optional_authentication_is_disabled() async throws {
        // Without `optionalAuthentication`, refresh errors must propagate so the
        // caller can surface them to the user instead of silently dropping the
        // request.
        let url = URL(string: "https://test.tuist.dev")!
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
        let response = HTTPResponse(status: 200)
        let error = RefreshAuthTokenServiceError.unauthorized("Invalid token")
        given(serverAuthenticationController).authenticationToken(
            serverURL: .value(url),
            refreshIfNeeded: .value(true)
        )
        .willThrow(error)

        // When
        let thrown = await #expect(throws: CredentialAcquisitionError.self, performing: {
            try await subject.intercept(
                request,
                body: nil,
                baseURL: url,
                operationID: "123"
            ) { _, _, _ in
                (response, nil)
            }
        })

        // Then
        #expect(thrown?.underlyingError as? RefreshAuthTokenServiceError == error)
    }

    @Test func returns_unauthorized_response_without_retrying() async throws {
        // Given
        let url = URL(string: "https://test.tuist.dev")!
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/api/projects")
        let token: AuthenticationToken = .user(
            accessToken: .test(token: "access-token"),
            refreshToken: .test(token: "refresh-token")
        )
        given(serverAuthenticationController).authenticationToken(
            serverURL: .value(url),
            refreshIfNeeded: .value(true)
        )
        .willReturn(token)

        var requestCount = 0

        // When
        let (response, _) = try await subject.intercept(
            request,
            body: nil,
            baseURL: url,
            operationID: "listProjects"
        ) { _, _, _ in
            requestCount += 1
            return (HTTPResponse(status: .init(code: 401)), nil)
        }

        // Then
        #expect(response.status.code == 401)
        #expect(requestCount == 1)
        verify(serverAuthenticationController)
            .refreshToken(
                serverURL: .any,
                inBackground: .any,
                locking: .any,
                forceInProcessLock: .any
            )
            .called(0)
    }

    @Test(arguments: [
        CredentialFailure.transport(.networkConnectionLost),
        .transport(.cannotConnectToHost),
        .refreshStatus(502),
        .refreshStatus(503),
    ])
    func does_not_replay_a_request_whose_credential_acquisition_failed(failure: CredentialFailure) async throws {
        // Given
        let url = URL(string: "https://test.tuist.dev")!
        let refreshes = CallCounter()
        given(serverAuthenticationController).authenticationToken(
            serverURL: .value(url),
            refreshIfNeeded: .value(true)
        )
        .willProduce { _, _ in
            guard refreshes.next() > 1 else { throw failure.error }
            return .project("project-token")
        }
        let transport = TeapotTransport()
        let client = Client(
            serverURL: url,
            transport: transport,
            middlewares: [RetryMiddleware(maxRetries: 4, baseDelayMilliseconds: 0), subject]
        )

        // When
        let thrown = await #expect(throws: ClientError.self) {
            _ = try await client.createProject(.init(body: .json(.init(full_handle: "acme/app"))))
        }

        // Then
        #expect(thrown.map { String(describing: $0.underlyingError) } == String(describing: failure.error))
        #expect(transport.requests.withLock { $0 } == 0)
        #expect(refreshes.count == 1)
    }

    @Test(arguments: [
        RefreshAuthTokenServiceError.unauthorized("The refresh token is expired or invalid"),
        .badRequest,
    ])
    func does_not_replay_a_request_whose_credential_refresh_was_rejected(
        error: RefreshAuthTokenServiceError
    ) async throws {
        // Given
        let url = URL(string: "https://test.tuist.dev")!
        let refreshes = CallCounter()
        given(serverAuthenticationController).authenticationToken(
            serverURL: .value(url),
            refreshIfNeeded: .value(true)
        )
        .willProduce { _, _ in
            _ = refreshes.next()
            throw error
        }
        let transport = ProjectsTransport()
        let client = Client(
            serverURL: url,
            transport: transport,
            middlewares: [RetryMiddleware(maxRetries: 4, baseDelayMilliseconds: 0), subject]
        )

        // When
        let thrown = await #expect(throws: ClientError.self) {
            _ = try await client.listProjects(.init())
        }

        // Then
        #expect(thrown?.underlyingError as? RefreshAuthTokenServiceError == error)
        #expect(transport.requests.withLock { $0 } == 0)
        #expect(refreshes.count == 1)
    }
}

private final class CallCounter: Sendable {
    private let calls = Mutex(0)

    var count: Int {
        calls.withLock { $0 }
    }

    func next() -> Int {
        calls.withLock { $0 += 1; return $0 }
    }
}

private final class ProjectsTransport: ClientTransport, Sendable {
    let requests = Mutex(0)

    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID _: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        requests.withLock { $0 += 1 }
        var response = HTTPResponse(status: .ok)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(#"{"projects":[]}"#))
    }
}

private final class TeapotTransport: ClientTransport, Sendable {
    let requests = Mutex(0)

    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID _: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        requests.withLock { $0 += 1 }
        return (HTTPResponse(status: 418), nil)
    }
}

enum CredentialFailure: Sendable, CustomTestStringConvertible {
    case transport(URLError.Code)
    case refreshStatus(Int)

    var error: any Error {
        switch self {
        case let .transport(code): URLError(code)
        case let .refreshStatus(code): RefreshAuthTokenServiceError.unknownError(code)
        }
    }

    var testDescription: String {
        switch self {
        case let .transport(code): "URLError \(code.rawValue)"
        case let .refreshStatus(code): "refresh HTTP \(code)"
        }
    }
}
