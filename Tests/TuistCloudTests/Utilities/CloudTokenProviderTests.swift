import Basic
import Foundation
import TuistSupport
import XCTest

@testable import TuistCloud
@testable import TuistSupportTesting

final class CloudTokenProviderTests: TuistUnitTestCase {
    var ciChecker: MockCIChecker!
    var credentialsStore: MockCredentialsStore!
    var subject: CloudTokenProvider!
    var environmentVariables: [String: String] = [:]
    var serverURL: URL!

    override func setUp() {
        super.setUp()
        ciChecker = MockCIChecker()
        credentialsStore = MockCredentialsStore()
        serverURL = URL.test()
        subject = CloudTokenProvider(ciChecker: ciChecker,
                                     environmentVariables: environmentVariables,
                                     credentialsStore: credentialsStore)
    }

    override func tearDown() {
        ciChecker = nil
        credentialsStore = nil
        subject = nil
        super.tearDown()
    }

    func test_read_when_CI() throws {
        // Given
        ciChecker.isCIStub = true
        let token = "TOKEN"
        environmentVariables[Constants.EnvironmentVariables.cloudToken] = token

        // When
        let got = try subject.read(serverURL: serverURL)

        // Then
        XCTAssertEqual(got, token)
    }

    func test_read_when_not_CI() throws {
        // Given
        ciChecker.isCIStub = false
        let token = "TOKEN"
        let credentials = Credentials(token: token, account: "test")
        try credentialsStore.store(credentials: credentials, serverURL: serverURL)

        // When
        let got = try subject.read(serverURL: serverURL)

        // Then
        XCTAssertEqual(got, token)
    }
}
