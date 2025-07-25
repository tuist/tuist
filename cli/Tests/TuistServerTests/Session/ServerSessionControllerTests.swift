import Foundation
import Mockable
import TuistSupport
import XCTest

@testable import TuistServer
@testable import TuistTesting

final class ServerSessionControllerTests: TuistUnitTestCase {
    private var credentialsStore: MockServerCredentialsStoring!
    private var opener: MockOpening!
    private var serverURL: URL!
    private var getAuthTokenService: MockGetAuthTokenServicing!
    private var uniqueIDGenerator: MockUniqueIDGenerating!
    private var serverAuthenticationController: MockServerAuthenticationControlling!
    private var subject: ServerSessionController!

    override func setUp() {
        super.setUp()
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

    override func tearDown() {
        credentialsStore = nil
        opener = nil
        serverURL = nil
        uniqueIDGenerator = nil
        serverAuthenticationController = nil
        subject = nil
        super.tearDown()
    }

    func test_authenticate_when_tokenAndAccountParametersAreIncluded() async throws {
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
        XCTAssertEqual(authURLOpened, authURL())
    }

    func test_whoami_when_logged_in() async throws {
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
        XCTAssertEqual(got, "tuist")
    }

    func test_whoami_when_logged_out() async throws {
        // Given
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(
                nil
            )

        // When
        let got = try await subject.whoami(serverURL: serverURL)

        // Then
        XCTAssertEqual(got, nil)
    }

    func test_get_authenticated_handle_when_logged_in() async throws {
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
        XCTAssertEqual(got, "tuist")
    }

    func test_get_authenticated_handle_when_logged_out() async throws {
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(
                nil
            )

        // Then
        await XCTAssertThrowsSpecific(
            try await subject.authenticatedHandle(serverURL: serverURL),
            ServerSessionControllerError.unauthenticated
        )
    }

    func test_logout_deletesCredentials() async throws {
        try await withMockedDependencies {
            // Given
            let serverCredentialsStore = try XCTUnwrap(ServerCredentialsStore.mocked)
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

    fileprivate func authURL() -> URL {
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)!
        components.path = "/auth/device_codes/\(uniqueIDGenerator.uniqueID())"
        components.queryItems = [
            URLQueryItem(name: "type", value: "cli"),
        ]
        return components.url!
    }
}
