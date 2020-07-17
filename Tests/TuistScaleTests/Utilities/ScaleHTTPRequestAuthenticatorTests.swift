import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistScale
@testable import TuistSupportTesting

final class ScaleHTTPRequestAuthenticatorTests: TuistUnitTestCase {
    var ciChecker: MockCIChecker!
    var credentialsStore: MockCredentialsStore!
    var subject: ScaleHTTPRequestAuthenticator!
    var environmentVariables: [String: String] = [:]

    override func setUp() {
        super.setUp()
        ciChecker = MockCIChecker()
        credentialsStore = MockCredentialsStore()
        subject = ScaleHTTPRequestAuthenticator(ciChecker: ciChecker,
                                                environmentVariables: { self.environmentVariables },
                                                credentialsStore: credentialsStore)
    }

    override func tearDown() {
        ciChecker = nil
        credentialsStore = nil
        subject = nil
        super.tearDown()
    }

    func test_authenticate_when_CI() throws {
        // Given
        ciChecker.isCIStub = true
        let token = "TOKEN"
        environmentVariables[Constants.EnvironmentVariables.scaleToken] = token
        let request = URLRequest(url: URL(string: "https://scale.tuist.io/path")!)

        // When
        let got = try subject.authenticate(request: request)

        // Then
        XCTAssertEqual(got.allHTTPHeaderFields?["Authorization"], "Bearer \(token)")
    }

    func test_authenticate_when_not_CI() throws {
        // Given
        ciChecker.isCIStub = false
        let token = "TOKEN"
        let credentials = Credentials(token: token, account: "test")
        try credentialsStore.store(credentials: credentials, serverURL: URL(string: "https://scale.tuist.io")!)
        let request = URLRequest(url: URL(string: "https://scale.tuist.io/path")!)

        // When
        let got = try subject.authenticate(request: request)

        // Then
        XCTAssertEqual(got.allHTTPHeaderFields?["Authorization"], "Bearer \(token)")
    }
}
