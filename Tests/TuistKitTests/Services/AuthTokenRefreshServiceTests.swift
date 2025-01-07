import Foundation
import Mockable
import Testing
import TuistServer
import TuistSupport

@testable import TuistKit

struct AuthTokenRefreshServiceTests {
    private let subject: AuthTokenRefreshService
    private let refreshAuthTokenService = MockRefreshAuthTokenServicing()
    private let serverCredentialsStore = MockServerCredentialsStoring()
    private let serverAuthenticationController = MockServerAuthenticationControlling()

    init() {
        subject = AuthTokenRefreshService(
            refreshAuthTokenService: refreshAuthTokenService,
            serverCredentialsStore: serverCredentialsStore,
            serverAuthenticationController: serverAuthenticationController
        )
    }

    @Test func stores_new_tokens() async throws {
        // Given
        let path = try TemporaryDirectory(removeTreeOnDeinit: true).path
        given(refreshAuthTokenService).refreshTokens(serverURL: .any, refreshToken: .value("token")).willReturn(.init(accessToken:
            "new-access-token", refreshToken: "new-refresh-token"))
        given(serverAuthenticationController).authenticationToken(serverURL: .any).willReturn(.user(
            legacyToken: nil,
            accessToken: .test(),
            refreshToken: .test()
        ))
        given(serverCredentialsStore)
            .store(credentials: .any, serverURL: .any)
            .willReturn()

        // When
        try await subject.refreshTokens(
            path: path
        )

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
    }
}
