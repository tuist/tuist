import Foundation
import HTTPTypes
import Mockable
import OpenAPIRuntime
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistServerCore

final class ServerClientAuthenticationMiddlewareTests: TuistUnitTestCase {
    private var subject: ServerClientAuthenticationMiddleware!
    private var serverAuthenticationController: MockServerAuthenticationControlling!
    private var serverCredentialsStore: MockServerCredentialsStoring!
    private var refreshAuthTokenService: MockRefreshAuthTokenServicing!
    private var cachedValueStore: MockCachedValueStoring!

    override func setUp() {
        super.setUp()

        serverAuthenticationController = .init()
        serverCredentialsStore = .init()
        refreshAuthTokenService = .init()
        subject = .init(
            serverAuthenticationController: serverAuthenticationController,
            serverCredentialsStore: serverCredentialsStore,
            refreshAuthTokenService: refreshAuthTokenService,
            cachedValueStore: CachedValueStore(),
            envVariables: [:]
        )
    }

    override func tearDown() {
        serverAuthenticationController = nil
        serverCredentialsStore = nil
        refreshAuthTokenService = nil
        subject = nil
        super.tearDown()
    }

    func test_when_cirrus_env_variable_is_present() async throws {
        // Given
        subject = .init(
            serverAuthenticationController: serverAuthenticationController,
            serverCredentialsStore: serverCredentialsStore,
            refreshAuthTokenService: refreshAuthTokenService,
            cachedValueStore: CachedValueStore(),
            envVariables: [Constants.EnvironmentVariables.cirrusTuistCacheURL: "https://cirrus.dev"]
        )
        let url = URL(string: "https://test.tuist.io")!
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
        let response = HTTPResponse(
            status: 200
        )
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
        XCTAssertEqual(gotResponse, response)
        XCTAssertEqual(
            gotRequest.headerFields,
            [:]
        )
    }

    func test_when_authentication_token_is_nil() async throws {
        let url = URL(string: "https://test.tuist.io")!
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
        let response = HTTPResponse(
            status: 200
        )

        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(nil)

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.intercept(
                request,
                body: nil,
                baseURL: url,
                operationID: "123"
            ) { _, _, _ in
                (response, nil)
            },
            ServerClientAuthenticationError.notAuthenticated
        )
    }

    func test_when_using_project_token() async throws {
        let url = URL(string: "https://test.tuist.io")!
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
        let response = HTTPResponse(
            status: 200
        )

        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("project-token"))

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
        XCTAssertEqual(gotResponse, response)
        XCTAssertEqual(
            gotRequest.headerFields,
            [
                .authorization: "Bearer project-token",
            ]
        )
    }

    func test_when_using_legacy_token() async throws {
        let url = URL(string: "https://test.tuist.io")!
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
        let response = HTTPResponse(
            status: 200
        )

        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.user(legacyToken: "legacy-token", accessToken: nil, refreshToken: nil))

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
        XCTAssertEqual(gotResponse, response)
        XCTAssertEqual(
            gotRequest.headerFields,
            [
                .authorization: "Bearer legacy-token",
            ]
        )
    }

    func test_when_using_valid_access_token() async throws {
        try await Date.$now.withValue({ Date(timeIntervalSince1970: 0) }) {
            let url = URL(string: "https://test.tuist.io")!
            let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
            let response = HTTPResponse(
                status: 200
            )

            given(serverAuthenticationController)
                .authenticationToken(serverURL: .any)
                .willReturn(
                    .user(
                        legacyToken: nil,
                        accessToken: .test(
                            token: "access-token",
                            expiryDate: Date(timeIntervalSince1970: 100)
                        ),
                        refreshToken: .test()
                    )
                )

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
            XCTAssertEqual(gotResponse, response)
            XCTAssertEqual(
                gotRequest.headerFields,
                [
                    .authorization: "Bearer access-token",
                ]
            )
        }
    }

    func test_when_access_token_is_expired() async throws {
        try await Date.$now.withValue({ Date(timeIntervalSince1970: 90) }) {
            let url = URL(string: "https://test.tuist.io")!
            let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
            let response = HTTPResponse(
                status: 200
            )

            given(serverAuthenticationController)
                .authenticationToken(serverURL: .any)
                .willReturn(
                    .user(
                        legacyToken: nil,
                        accessToken: .test(
                            token: "access-token",
                            expiryDate: Date(timeIntervalSince1970: 100)
                        ),
                        refreshToken: .test(
                            token: "refresh-token",
                            expiryDate: Date(timeIntervalSince1970: 1000)
                        )
                    )
                )

            var gotRequest: HTTPRequest!

            given(refreshAuthTokenService)
                .refreshTokens(serverURL: .any, refreshToken: .value("refresh-token"))
                .willReturn(
                    ServerAuthenticationTokens(
                        accessToken: "new-access-token",
                        refreshToken: "new-refresh-token"
                    )
                )

            given(serverCredentialsStore)
                .store(credentials: .any, serverURL: .any)
                .willReturn()

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
            verify(serverCredentialsStore)
                .store(
                    credentials: .value(
                        ServerCredentials(
                            token: nil,
                            accessToken: "new-access-token",
                            refreshToken: "new-refresh-token"
                        )
                    ),
                    serverURL: .any
                )
                .called(1)

            XCTAssertEqual(gotResponse, response)
            XCTAssertEqual(
                gotRequest.headerFields,
                [
                    .authorization: "Bearer new-access-token",
                ]
            )
        }
    }
}
