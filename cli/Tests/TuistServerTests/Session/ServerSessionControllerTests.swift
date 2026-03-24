import Foundation
import Mockable
import Testing
import TuistOpener
import TuistSupport
import TuistUniqueIDGenerator

@testable import TuistServer
@testable import TuistTesting

struct ServerSessionControllerTests {
    private let credentialsStore: MockServerCredentialsStoring
    private let opener: MockOpening
    private let serverURL: URL
    private let getAuthTokenService: MockGetAuthTokenServicing
    private let uniqueIDGenerator: MockUniqueIDGenerating
    private let serverAuthenticationController: MockServerAuthenticationControlling
    private let subject: ServerSessionController
    init() {
        credentialsStore = .init()
        serverURL = URL.test()
        getAuthTokenService = MockGetAuthTokenServicing()
        uniqueIDGenerator = MockUniqueIDGenerating()
        serverAuthenticationController = MockServerAuthenticationControlling()
        opener = MockOpening()
        subject = ServerSessionController(
            opener: opener,
            getAuthTokenService: getAuthTokenService,
            uniqueIDGenerator: uniqueIDGenerator,
            serverAuthenticationController: serverAuthenticationController
        )
        given(opener)
            .open(url: .any)
            .willReturn()
    }

    @Test
    func authenticate_when_tokenAndAccountParametersAreIncluded() async throws {
        // Given
        given(getAuthTokenService)
            .getAuthToken(serverURL: .any, deviceCode: .any)
            .willReturn(
                ServerAuthenticationTokens(
                    accessToken: "access-token", refreshToken: "refresh-token"
                )
            )
        given(uniqueIDGenerator).uniqueID().willReturn("id")
        given(credentialsStore)
            .read(serverURL: .value(serverURL))
            .willReturn(
                ServerCredentials(
                    accessToken: "access-token", refreshToken: "refresh-token"
                )
            )
        given(credentialsStore)
            .store(credentials: .any, serverURL: .value(serverURL))
            .willReturn()

        // When
        var authURLOpened: URL?
        try await subject.authenticate(
            serverURL: serverURL,
            deviceCodeType: .cli,
            onOpeningBrowser: { authURLOpened = $0 },
            onAuthWaitBegin: {}
        )

        // Then
        #expect(authURLOpened == authURL())
    }

    @Test
    func whoami_when_logged_in() async throws {
        // Given
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(
                .user(
                    accessToken: .test(
                        email: "tuist@tuist.dev",
                        preferredUsername: "tuist"
                    ),
                    refreshToken: .test(
                        email: "tuist@tuist.dev",
                        preferredUsername: "tuist"
                    )
                )
            )

        // When
        let got = try await subject.whoami(serverURL: serverURL)

        // Then
        #expect(got == "tuist")
    }

    @Test
    func whoami_when_logged_out() async throws {
        // Given
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(
                nil
            )

        // When
        let got = try await subject.whoami(serverURL: serverURL)

        // Then
        #expect(got == nil)
    }

    @Test
    func get_authenticated_handle_when_logged_in() async throws {
        // Given
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(
                .user(
                    accessToken: .test(
                        email: "tuist@tuist.dev",
                        preferredUsername: "tuist"
                    ),
                    refreshToken: .test(
                        email: "tuist@tuist.dev",
                        preferredUsername: "tuist"
                    )
                )
            )

        // When
        let got = try await subject.whoami(serverURL: serverURL)

        // Then
        #expect(got == "tuist")
    }

    @Test
    func get_authenticated_handle_when_logged_out() async throws {
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(
                nil
            )

        // Then
        await #expect(throws: ServerSessionControllerError.unauthenticated) {
            try await subject.authenticatedHandle(serverURL: serverURL)
        }
    }

    @Test
    func logout_deletesCredentials() async throws {
        try await withMockedDependencies {
            // Given
            let serverCredentialsStore = try #require(ServerCredentialsStore.mocked)
            given(serverCredentialsStore)
                .delete(serverURL: .any)
                .willReturn()
            let credentials = ServerCredentials(
                accessToken: "access-token",
                refreshToken: "refresh-token"
            )
            given(credentialsStore)
                .store(credentials: .value(credentials), serverURL: .value(serverURL))
                .willReturn()
            try await credentialsStore.store(credentials: credentials, serverURL: serverURL)

            given(credentialsStore)
                .delete(serverURL: .value(serverURL))
                .willReturn()

            // When
            try await subject.logout(serverURL: serverURL)
        }
    }

    private func authURL() -> URL {
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)!
        components.path = "/auth/device_codes/\(uniqueIDGenerator.uniqueID())"
        components.queryItems = [
            URLQueryItem(name: "type", value: "cli"),
        ]
        return components.url!
    }
}
