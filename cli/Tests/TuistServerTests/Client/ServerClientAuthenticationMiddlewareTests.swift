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
    private var serverCredentialsStore: MockServerCredentialsStoring!
    private var refreshAuthTokenService: MockRefreshAuthTokenServicing!
    private var cachedValueStore: MockCachedValueStoring!

    init() {
        serverAuthenticationController = .init()
        serverCredentialsStore = .init()
        refreshAuthTokenService = .init()
        subject = .init(
            serverAuthenticationController: serverAuthenticationController,
            serverCredentialsStore: serverCredentialsStore,
            refreshAuthTokenService: refreshAuthTokenService,
            cachedValueStore: CachedValueStore()
        )
    }

    @Test(.withMockedEnvironment()) func test_when_authentication_token_is_nil() async throws {
        let url = URL(string: "https://test.tuist.io")!
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
        let response = HTTPResponse(
            status: 200
        )

        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
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

    @Test func test_when_using_project_token() async throws {
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
        #expect(gotResponse == response)
        #expect(
            gotRequest.headerFields ==
                [
                    .authorization: "Bearer project-token",
                ]
        )
    }

    @Test func test_when_using_legacy_token() async throws {
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
        #expect(gotResponse == response)
        #expect(
            gotRequest.headerFields ==
                [
                    .authorization: "Bearer legacy-token",
                ]
        )
    }

    @Test func test_when_using_valid_access_token() async throws {
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
            #expect(gotResponse == response)
            #expect(
                gotRequest.headerFields ==
                    [
                        .authorization: "Bearer access-token",
                    ]
            )
        }
    }

    @Test func test_when_access_token_is_expired() async throws {
        try await Date.$now.withValue({ Date(timeIntervalSince1970: 90) }) {
            let url = URL(string: "https://test.tuist.io")!
            let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
            let response = HTTPResponse(
                status: 200
            )
            let refreshToken =
                "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiYWRtaW4iOnRydWUsImlhdCI6MTUxNjIzOTAyMiwiZXhwIjoxNzQ5MjEwNzUzfQ.TIQpQLlQWd-BIs46rBHPM-WMC2MhvX2jrCLqh14B-1U"
            given(serverAuthenticationController)
                .authenticationToken(serverURL: .any)
                .willReturn(
                    .user(
                        legacyToken: nil,
                        accessToken: .test(
                            token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiYWRtaW4iOnRydWUsImlhdCI6MTUxNjIzOTAyMiwiZXhwIjoxNzQ5MjEwNzUyfQ.2NnjKbxBfXoYjhiExFTSjf70nv0kfC2f6Jjv2YuO4p8",
                            expiryDate: Date(timeIntervalSince1970: 100)
                        ),
                        refreshToken: .test(
                            token: refreshToken,
                            expiryDate: Date(timeIntervalSince1970: 1000)
                        )
                    )
                )

            var gotRequest: HTTPRequest!
            let newAccessToken =
                "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiYWRtaW4iOnRydWUsImlhdCI6MTUxNjIzOTAyMiwiZXhwIjoxNzQ5MjEwNzk5fQ.cM4h02as3xFwA8lH24EVdZItfBiTiToJfxpgZE5lBRM"
            let newRefreshToken =
                "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiYWRtaW4iOnRydWUsImlhdCI6MTUxNjIzOTAyMiwiZXhwIjoxNzQ5MjEwODAwfQ.xTEz5fWUpIImcKC2MtQWiQ0xhQrVKDPbuBqr4vdBtlc"
            given(refreshAuthTokenService)
                .refreshTokens(serverURL: .any, refreshToken: .value(refreshToken))
                .willReturn(
                    ServerAuthenticationTokens(
                        accessToken: newAccessToken,
                        refreshToken: newRefreshToken
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
                            accessToken: newAccessToken,
                            refreshToken: newRefreshToken
                        )
                    ),
                    serverURL: .any
                )
                .called(1)

            #expect(gotResponse == response)
            #expect(
                gotRequest.headerFields ==
                    [
                        .authorization: "Bearer \(newAccessToken)",
                    ]
            )
        }
    }
}
