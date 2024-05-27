import Foundation
import Mockable
import MockableTest
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistServer
@testable import TuistSupportTesting

final class CloudSessionControllerTests: TuistUnitTestCase {
    private var credentialsStore: MockCloudCredentialsStoring!
    private var ciChecker: MockCIChecker!
    private var opener: MockOpener!
    private var serverURL: URL!
    private var getAuthTokenService: MockGetAuthTokenServicing!
    private var uniqueIDGenerator: MockUniqueIDGenerating!
    private var cloudAuthenticationController: MockCloudAuthenticationControlling!
    private var subject: CloudSessionController!

    override func setUp() {
        super.setUp()
        credentialsStore = .init()
        ciChecker = MockCIChecker()
        opener = MockOpener()
        serverURL = URL.test()
        getAuthTokenService = MockGetAuthTokenServicing()
        uniqueIDGenerator = MockUniqueIDGenerating()
        cloudAuthenticationController = MockCloudAuthenticationControlling()
        subject = CloudSessionController(
            credentialsStore: credentialsStore,
            ciChecker: ciChecker,
            opener: opener,
            getAuthTokenService: getAuthTokenService,
            uniqueIDGenerator: uniqueIDGenerator,
            cloudAuthenticationController: cloudAuthenticationController
        )
    }

    override func tearDown() {
        credentialsStore = nil
        ciChecker = nil
        opener = nil
        serverURL = nil
        uniqueIDGenerator = nil
        cloudAuthenticationController = nil
        subject = nil
        super.tearDown()
    }

    func test_authenticate_when_tokenAndAccountParametersAreIncluded() async throws {
        // Given
        given(getAuthTokenService).getAuthToken(serverURL: .any, deviceCode: .any).willReturn("token")
        given(uniqueIDGenerator).uniqueID().willReturn("id")
        given(credentialsStore)
            .read(serverURL: .value(serverURL))
            .willReturn(CloudCredentials(token: "token"))

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
        given(cloudAuthenticationController).authenticationToken(serverURL: .value(serverURL)).willReturn(.user("token"))
        try subject.printSession(serverURL: serverURL)

        // Then
        XCTAssertPrinterOutputContains("""
        Requests against \(serverURL.absoluteString) will be authenticated as a user using the following token:
        token
        """)
    }

    func test_printSession_when_projectToken() throws {
        // When
        given(cloudAuthenticationController).authenticationToken(serverURL: .value(serverURL)).willReturn(.project("token"))
        try subject.printSession(serverURL: serverURL)

        // Then
        XCTAssertPrinterOutputContains("""
        Requests against \(serverURL.absoluteString) will be authenticated as a project using the following token:
        token
        """)
    }

    func test_printSession_when_credentialsDontExist() throws {
        // Given
        given(cloudAuthenticationController).authenticationToken(serverURL: .value(serverURL)).willReturn(nil)

        // When
        try subject.printSession(serverURL: serverURL)

        // Then
        XCTAssertPrinterOutputContains("""
        There are no sessions for the server with URL \(serverURL.absoluteString)
        """)
    }

    func test_logout_deletesTheCredentials() throws {
        // Given
        let credentials = CloudCredentials(token: "token")
        try credentialsStore.store(credentials: credentials, serverURL: serverURL)

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
