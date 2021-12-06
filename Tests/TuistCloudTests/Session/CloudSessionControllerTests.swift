import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistCloud
@testable import TuistSupportTesting

final class CloudSessionControllerErrorTests: TuistUnitTestCase {
    func test_description_when_missingParameters() {
        // Given
        let subject = CloudSessionControllerError.missingParameters

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "The result from the authentication contains no parameters. We expect an account and token.")
    }

    func test_type_when_missingParameters() {
        // Given
        let subject = CloudSessionControllerError.missingParameters

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .abort)
    }

    func test_description_when_authenticationError() {
        // Given
        let subject = CloudSessionControllerError.authenticationError("error")

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "error")
    }

    func test_type_when_authenticationError() {
        // Given
        let subject = CloudSessionControllerError.authenticationError("error")

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .abort)
    }

    func test_description_when_invalidParameters() {
        // Given
        let subject = CloudSessionControllerError.invalidParameters(["invalid"])

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(
            got,
            "The result from the authentication contains invalid parameters: invalid. We expect an account and token."
        )
    }

    func test_type_when_invalidParameters() {
        // Given
        let subject = CloudSessionControllerError.invalidParameters(["invalid"])

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .abort)
    }
}

final class CloudSessionControllerTests: TuistUnitTestCase {
    var credentialsStore: MockCredentialsStore!
    var httpRedirectListener: MockHTTPRedirectListener!
    var ciChecker: MockCIChecker!
    var opener: MockOpener!
    var serverURL: URL!
    var subject: CloudSessionController!

    override func setUp() {
        super.setUp()
        credentialsStore = MockCredentialsStore()
        httpRedirectListener = MockHTTPRedirectListener()
        ciChecker = MockCIChecker()
        opener = MockOpener()
        serverURL = URL.test()
        subject = CloudSessionController(
            credentialsStore: credentialsStore,
            httpRedirectListener: httpRedirectListener,
            ciChecker: ciChecker,
            opener: opener
        )
    }

    override func tearDown() {
        credentialsStore = nil
        httpRedirectListener = nil
        ciChecker = nil
        opener = nil
        serverURL = nil
        subject = nil
        super.tearDown()
    }

    func test_authenticate_when_parametersAreMissing() throws {
        // Given
        httpRedirectListener
            .listenStub = { port, path, message, _ -> (Swift.Result<[String: String]?, HTTPRedirectListenerError>) in
                XCTAssertEqual(port, CloudSessionController.port)
                XCTAssertEqual(path, "auth")
                XCTAssertEqual(message, "Switch back to your terminal to continue the authentication.")
                return .success(nil)
            }

        // Then
        XCTAssertThrowsSpecific(try subject.authenticate(serverURL: serverURL), CloudSessionControllerError.missingParameters)
        XCTAssertPrinterOutputContains("""
        Opening \(authURL().absoluteString) to start the authentication flow
        """)
    }

    func test_authenticate_when_parametersIncludeError() throws {
        // Given
        httpRedirectListener
            .listenStub = { port, path, message, _ -> (Swift.Result<[String: String]?, HTTPRedirectListenerError>) in
                XCTAssertEqual(port, CloudSessionController.port)
                XCTAssertEqual(path, "auth")
                XCTAssertEqual(message, "Switch back to your terminal to continue the authentication.")
                return .success(["error": "value"])
            }

        // Then
        XCTAssertThrowsSpecific(
            try subject.authenticate(serverURL: serverURL),
            CloudSessionControllerError.authenticationError("value")
        )
        XCTAssertPrinterOutputContains("""
        Opening \(authURL().absoluteString) to start the authentication flow
        """)
    }

    func test_authenticate_when_tokenAndAccountParametersAreIncluded() throws {
        // Given
        httpRedirectListener
            .listenStub = { port, path, message, _ -> (Swift.Result<[String: String]?, HTTPRedirectListenerError>) in
                XCTAssertEqual(port, CloudSessionController.port)
                XCTAssertEqual(path, "auth")
                XCTAssertEqual(message, "Switch back to your terminal to continue the authentication.")
                return .success(["account": "account", "token": "token"])
            }

        // When
        try subject.authenticate(serverURL: serverURL)

        // Then
        let expectedCredentials = Credentials(token: "token", account: "account")
        XCTAssertEqual(try credentialsStore.read(serverURL: serverURL), expectedCredentials)
        XCTAssertPrinterOutputContains("""
        Opening \(authURL().absoluteString) to start the authentication flow
        Successfully authenticated. Storing credentials...
        Credentials stored successfully
        """)
    }

    func test_authenticate_when_parametersContainInvalidKeys() throws {
        // Given
        httpRedirectListener
            .listenStub = { port, path, message, _ -> (Swift.Result<[String: String]?, HTTPRedirectListenerError>) in
                XCTAssertEqual(port, CloudSessionController.port)
                XCTAssertEqual(path, "auth")
                XCTAssertEqual(message, "Switch back to your terminal to continue the authentication.")
                return .success(["invalid": "value"])
            }

        // Then
        XCTAssertThrowsSpecific(
            try subject.authenticate(serverURL: serverURL),
            CloudSessionControllerError.invalidParameters(["invalid"])
        )
        XCTAssertPrinterOutputContains("""
        Opening \(authURL().absoluteString) to start the authentication flow
        """)
    }

    func test_printSession_when_credentialsExist() throws {
        // When
        let credentials = Credentials(token: "token", account: "account")
        try credentialsStore.store(credentials: credentials, serverURL: serverURL)
        try subject.printSession(serverURL: serverURL)

        // Then
        XCTAssertPrinterOutputContains("""
        These are the credentials for the server with URL \(serverURL.absoluteString):
        - Account: \(credentials.account)
        - Token: \(credentials.token)
        """)
    }

    func test_printSession_when_credentialsDontExist() throws {
        // When
        try subject.printSession(serverURL: serverURL)

        // Then
        XCTAssertPrinterOutputContains("""
        There are no sessions for the server with URL \(serverURL.absoluteString)
        """)
    }

    func test_logout_deletesTheCredentials() throws {
        // Given
        let credentials = Credentials(token: "token", account: "account")
        try credentialsStore.store(credentials: credentials, serverURL: serverURL)
        XCTAssertNotNil(try credentialsStore.read(serverURL: serverURL))

        // When
        try subject.logout(serverURL: serverURL)

        // Then
        XCTAssertNil(try credentialsStore.read(serverURL: serverURL))
        XCTAssertPrinterOutputContains("""
        Removing session for server with URL \(serverURL.absoluteString)
        Session deleted successfully
        """)
    }

    fileprivate func authURL() -> URL {
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)!
        components.path = "/auth"
        components.queryItems = nil
        return components.url!
    }
}
