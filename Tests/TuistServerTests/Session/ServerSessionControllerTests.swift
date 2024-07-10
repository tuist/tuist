import Foundation
import Mockable
import MockableTest
import Path
import TuistSupport
import XCTest

@testable import TuistServer
@testable import TuistSupportTesting

final class ServerSessionControllerTests: TuistUnitTestCase {
    private var credentialsStore: MockServerCredentialsStoring!
    private var ciChecker: MockCIChecker!
    private var opener: MockOpener!
    private var serverURL: URL!
    private var getAuthTokenService: MockGetAuthTokenServicing!
    private var uniqueIDGenerator: MockUniqueIDGenerating!
    private var serverAuthenticationController: MockServerAuthenticationControlling!
    private var subject: ServerSessionController!

    override func setUp() {
        super.setUp()
        credentialsStore = .init()
        ciChecker = MockCIChecker()
        opener = MockOpener()
        serverURL = URL.test()
        getAuthTokenService = MockGetAuthTokenServicing()
        uniqueIDGenerator = MockUniqueIDGenerating()
        serverAuthenticationController = MockServerAuthenticationControlling()
        subject = ServerSessionController(
            credentialsStore: credentialsStore,
            ciChecker: ciChecker,
            opener: opener,
            getAuthTokenService: getAuthTokenService,
            uniqueIDGenerator: uniqueIDGenerator,
            serverAuthenticationController: serverAuthenticationController
        )
    }

    override func tearDown() {
        credentialsStore = nil
        ciChecker = nil
        opener = nil
        serverURL = nil
        uniqueIDGenerator = nil
        serverAuthenticationController = nil
        subject = nil
        super.tearDown()
    }

    func test_authenticate_when_tokenAndAccountParametersAreIncluded() async throws {
        // Given
        given(getAuthTokenService).getAuthToken(serverURL: .any, deviceCode: .any).willReturn("token")
        given(uniqueIDGenerator).uniqueID().willReturn("id")
        given(credentialsStore)
            .read(serverURL: .value(serverURL))
            .willReturn(ServerCredentials(token: "token"))
        given(credentialsStore)
            .store(credentials: .any, serverURL: .value(serverURL))
            .willReturn()

        // When
        try await subject.authenticate(serverURL: serverURL)

        // Then
        XCTAssertPrinterOutputContains("""
        Opening \(authURL().absoluteString) to start the authentication flow
        Press CTRL + C once to cancel the process.
        Credentials stored successfully
        """)
    }

    func test_printSession_when_userToken() throws {
        // When
        given(serverAuthenticationController).authenticationToken(serverURL: .value(serverURL)).willReturn(.user("token"))
        try subject.printSession(serverURL: serverURL)

        // Then
        XCTAssertPrinterOutputContains("""
        Requests against \(serverURL.absoluteString) will be authenticated as a user using the following token:
        token
        """)
    }

    func test_printSession_when_projectToken() throws {
        // When
        given(serverAuthenticationController).authenticationToken(serverURL: .value(serverURL)).willReturn(.project("token"))
        try subject.printSession(serverURL: serverURL)

        // Then
        XCTAssertPrinterOutputContains("""
        Requests against \(serverURL.absoluteString) will be authenticated as a project using the following token:
        token
        """)
    }

    func test_printSession_when_credentialsDontExist() throws {
        // Given
        given(serverAuthenticationController).authenticationToken(serverURL: .value(serverURL)).willReturn(nil)

        // When
        try subject.printSession(serverURL: serverURL)

        // Then
        XCTAssertPrinterOutputContains("""
        There are no sessions for the server with URL \(serverURL.absoluteString)
        """)
    }

    func test_logout_deletesTheCredentials() throws {
        // Given
        let credentials = ServerCredentials(token: "token")
        given(credentialsStore)
            .store(credentials: .value(credentials), serverURL: .value(serverURL))
            .willReturn()
        try credentialsStore.store(credentials: credentials, serverURL: serverURL)

        given(credentialsStore)
            .delete(serverURL: .value(serverURL))
            .willReturn()

        // When
        try subject.logout(serverURL: serverURL)

        // Then
        XCTAssertPrinterOutputContains("""
        Removing session for server with URL \(serverURL.absoluteString)
        Session deleted successfully
        """)
    }

    fileprivate func authURL() -> URL {
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)!
        components.path = "/auth/cli/\(uniqueIDGenerator.uniqueID())"
        components.queryItems = nil
        return components.url!
    }
}
