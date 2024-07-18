import Foundation
import MockableTest
import OpenAPIRuntime
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistServer

final class ServerClientAuthenticationMiddlewareTests: TuistUnitTestCase {
    private var subject: ServerClientAuthenticationMiddleware!
    private var serverAuthenticationController: MockServerAuthenticationControlling!
    private var serverCredentialsStore: MockServerCredentialsStoring!
    private var refreshAuthTokenService: MockRefreshAuthTokenServicing!
    private var dateService: MockDateServicing!

    override func setUp() {
        super.setUp()

        serverAuthenticationController = .init()
        serverCredentialsStore = .init()
        refreshAuthTokenService = .init()
        dateService = .init()
        subject = .init(
            serverAuthenticationController: serverAuthenticationController,
            serverCredentialsStore: serverCredentialsStore,
            refreshAuthTokenService: refreshAuthTokenService,
            dateService: dateService
        )
    }

    override func tearDown() {
        serverAuthenticationController = nil
        serverCredentialsStore = nil
        refreshAuthTokenService = nil
        dateService = nil
        subject = nil
        super.tearDown()
    }

    func test_when_authentication_token_is_nil() async throws {
        let url = URL(string: "https://test.tuist.io")!
        let request = Request(path: "/", method: .get)
        let response = Response(
            statusCode: 200
        )

        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(nil)

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.intercept(
                request,
                baseURL: url,
                operationID: "123"
            ) { _, _ in
                response
            },
            ServerClientAuthenticationError.notAuthenticated
        )
    }

    func test_when_using_project_token() async throws {
        let url = URL(string: "https://test.tuist.io")!
        let request = Request(path: "/", method: .get)
        let response = Response(
            statusCode: 200
        )

        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("project-token"))

        var gotRequest: Request!

        // When
        let gotResponse = try await subject.intercept(
            request,
            baseURL: url,
            operationID: "123"
        ) { request, _ in
            gotRequest = request
            return response
        }

        // Then
        XCTAssertEqual(gotResponse, response)
        XCTAssertEqual(
            gotRequest.headerFields,
            [
                HeaderField(
                    name: "Authorization", value: "Bearer project-token"
                ),
            ]
        )
    }

    func test_when_using_legacy_token() async throws {
        let url = URL(string: "https://test.tuist.io")!
        let request = Request(path: "/", method: .get)
        let response = Response(
            statusCode: 200
        )

        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.user(legacyToken: "legacy-token", accessToken: nil, refreshToken: nil))

        var gotRequest: Request!

        // When
        let gotResponse = try await subject.intercept(
            request,
            baseURL: url,
            operationID: "123"
        ) { request, _ in
            gotRequest = request
            return response
        }

        // Then
        XCTAssertEqual(gotResponse, response)
        XCTAssertEqual(
            gotRequest.headerFields,
            [
                HeaderField(
                    name: "Authorization", value: "Bearer legacy-token"
                ),
            ]
        )
    }

    func test_when_using_valid_access_token() async throws {
        let url = URL(string: "https://test.tuist.io")!
        let request = Request(path: "/", method: .get)
        let response = Response(
            statusCode: 200
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

        var gotRequest: Request!

        given(dateService)
            .now()
            .willReturn(Date(timeIntervalSince1970: 0))

        // When
        let gotResponse = try await subject.intercept(
            request,
            baseURL: url,
            operationID: "123"
        ) { request, _ in
            gotRequest = request
            return response
        }

        // Then
        XCTAssertEqual(gotResponse, response)
        XCTAssertEqual(
            gotRequest.headerFields,
            [
                HeaderField(
                    name: "Authorization", value: "Bearer access-token"
                ),
            ]
        )
    }

    func test_when_access_token_is_expired() async throws {
        let url = URL(string: "https://test.tuist.io")!
        let request = Request(path: "/", method: .get)
        let response = Response(
            statusCode: 200
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

        var gotRequest: Request!

        given(dateService)
            .now()
            .willReturn(Date(timeIntervalSince1970: 90))

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
        let gotResponse = try await subject.intercept(
            request,
            baseURL: url,
            operationID: "123"
        ) { request, _ in
            gotRequest = request
            return response
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
                HeaderField(
                    name: "Authorization", value: "Bearer new-access-token"
                ),
            ]
        )
    }
}
